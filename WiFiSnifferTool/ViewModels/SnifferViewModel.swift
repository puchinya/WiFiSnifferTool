import SwiftUI
import CoreWLAN
import ServiceManagement
import Combine

@MainActor
@Observable
class SnifferViewModel {
    var isCapturing: Bool = false
    var isProcessing: Bool = false
    var statusMessage: String = "待機中"
    var requiresApproval: Bool = false
    
    // ネットワーク設定
    var selectedInterface: String = "en0" {
        didSet {
            updateAvailableChannels()
        }
    }
    var selectedChannel: Int = 1 {
        didSet {
            updateAvailableWidths()
        }
    }
    var selectedChannelWidth: Int = 20
    var outputPipePath: String = "/tmp/wifi_sniffer.pipe"
    
    // UI用データ
    var availableInterfaces: [String] = []
    var availableChannels: [Int] = []
    var availableWidths: [Int] = []
    
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }
    
    // ヘルパーとのXPC接続
    private var connection: NSXPCConnection?
    
    // Wiresharkの外部プロセスを管理
    private var wiresharkProcess: Process?
    
    // アプリ終了イベント監視用
    private var cancellables = Set<AnyCancellable>()
    
    // CoreWLANクライアントから取得した生のチャンネル情報キャッシュ
    private var cachedWLANChannels: [CWChannel] = []
    
    init() {
        installHelperIfNeeded()
        fetchInterfaces()
        setupAppLifecycleObserver()
    }
    
    // インスタンス破棄時（画面遷移やViewModel解放時）のライフサイクル
    deinit {
        // deinitはnonisolatedなため、MainActor孤立プロパティに直接アクセスできません。
        // ここでは安全のため、フラグチェックのみを行い、実際のリソース解放は
        // setupAppLifecycleObserver で管理される willTerminateNotification 等に任せます。
        // ※ 完全にアプリが落ちる直前のクリーンアップは setupAppLifecycleObserver で行われます。
    }
    
    // アプリ全体の終了イベント（Cmd + Qなど）を監視する設定
    private func setupAppLifecycleObserver() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                print("アプリが終了します。キャプチャをクリーンアップします。")
                Task { @MainActor in
                    self?.executeImmediateCleanup()
                }
            }
            .store(in: &cancellables)
    }
    
    // アプリ終了時に非同期コールバックを待たずに即時リソースを解放するメソッド
    private func executeImmediateCleanup() {
        // 1. Wiresharkプロセスの強制終了
        if let process = wiresharkProcess, process.isRunning {
            process.terminationHandler = nil // ループを防ぐためハンドラをクリア
            process.terminate()
        }
        wiresharkProcess = nil
        
        // 2. ヘルパー（XPC）への最後の停止通知（同期的に呼び出して終了を確実にする）
        if let helper = connection?.remoteObjectProxy as? WiFiCaptureHelperProtocol {
            helper.stopCapture { _ in }
        }
        
        // 3. XPC接続の切断
        connection?.invalidate()
        connection = nil
    }
    
    private func installHelperIfNeeded() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "jp.daradara.WiFiSnifferToolHelper.plist")
            
            // 定期的に状態を確認して、ユーザーが設定で許可したのを検知する
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if service.status == .enabled {
                    self?.requiresApproval = false
                    self?.statusMessage = String(localized: "待機中")
                    timer.invalidate()
                }
            }

            if service.status == .requiresApproval {
                requiresApproval = true
                statusMessage = String(localized: "システム設定でヘルパーの実行を許可してください")
                return
            }
            if service.status != .enabled {
                do {
                    try service.register()
                    print("ヘルパーを登録しました")
                } catch {
                    print("ヘルパーの登録に失敗しました: \(error)")
                    statusMessage = String(localized: "ヘルパーツールのインストールに失敗しました")
                }
            } else {
                print("ヘルパーは既に登録されています")
                requiresApproval = false
            }
        }
    }
    
    // システム設定の「ログイン項目」を開く
    func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    
    // ヘルパーのアンインストール
    func uninstallHelper() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "jp.daradara.WiFiSnifferToolHelper.plist")
            do {
                try service.unregister()
                statusMessage = String(localized: "ヘルパーをアンインストールしました")
                requiresApproval = false
                print("ヘルパーの登録を解除しました")
            } catch {
                print("ヘルパーの解除に失敗しました: \(error)")
                statusMessage = String(localized: "アンインストールに失敗しました")
            }
        }
    }
    
    func fetchInterfaces() {
        let client = CWWiFiClient.shared()
        availableInterfaces = client.interfaces()?.compactMap { $0.interfaceName } ?? ["en0"]
        if let first = availableInterfaces.first {
            selectedInterface = first
        } else {
            updateAvailableChannels()
        }
    }
    
    private func updateAvailableChannels() {
        guard let interface = CWWiFiClient.shared().interface(withName: selectedInterface),
              let channels = interface.supportedWLANChannels() else {
            availableChannels = []
            cachedWLANChannels = []
            return
        }
        
        cachedWLANChannels = Array(channels)
        
        let uniqueChannels = Set(cachedWLANChannels.map { $0.channelNumber })
        availableChannels = Array(uniqueChannels).sorted()
        
        if !availableChannels.contains(selectedChannel), let firstChannel = availableChannels.first {
            selectedChannel = firstChannel
        } else {
            updateAvailableWidths()
        }
    }
    
    private func updateAvailableWidths() {
        let channelsForSelectedNumber = cachedWLANChannels.filter { $0.channelNumber == selectedChannel }
        
        var widths = Set<Int>()
        for channel in channelsForSelectedNumber {
            switch channel.channelWidth {
            case .width20MHz: widths.insert(20)
            case .width40MHz: widths.insert(40)
            case .width80MHz: widths.insert(80)
            case .width160MHz: widths.insert(160)
            default: break
            }
        }
        
        availableWidths = Array(widths).sorted()
        
        if availableWidths.isEmpty {
            availableWidths = [20]
        }
        
        if !availableWidths.contains(selectedChannelWidth), let firstWidth = availableWidths.first {
            selectedChannelWidth = firstWidth
        }
    }
    
    private func setupXPCConnection() -> WiFiCaptureHelperProtocol? {
        if connection == nil {
            let machServiceName = "jp.daradara.WiFiSnifferToolHelper"
            connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: WiFiCaptureHelperProtocol.self)
            
            connection?.interruptionHandler = { [weak self] in
                print("XPC Connection Interrupted")
                self?.handleXPCError()
            }
            connection?.invalidationHandler = { [weak self] in
                print("XPC Connection Invalidated")
                self?.handleXPCError()
            }
            
            connection?.resume()
        }
        
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            print("XPC Error: \(error.localizedDescription)")
            self?.handleXPCError()
        } as? WiFiCaptureHelperProtocol
    }
    
    private func handleXPCError() {
        Task { @MainActor in
            // 意図的な停止中、またはWireshark経由での停止（SIGPIPE等によるヘルパー終了）
            // の場合は、切断メッセージを表示せず、静かに状態を戻す
            if self.isCapturing && !self.isProcessing {
                self.statusMessage = String(localized: "ヘルパーツールとの通信が切断されました")
            }
            self.isCapturing = false
            self.isProcessing = false
            self.connection = nil
            // Wiresharkが動いている場合は、ここでは終了させない（Wireshark側の停止操作を尊重する）
        }
    }
    
    // キャプチャの開始
    func startCapture() {
        guard !isProcessing else { return }
        
        guard let helper = setupXPCConnection() else {
            statusMessage = String(localized: "ヘルパーツールに接続できません。インストールされているか確認してください。")
            return
        }
        
        isProcessing = true
        statusMessage = String(localized: "キャプチャを開始しています...")
        
        helper.startCapture(onInterface: selectedInterface,
                            channel: selectedChannel,
                            width: selectedChannelWidth,
                            outputNamedPipe: outputPipePath) { [weak self] errorString in
            // MainActor クラスなので DispatchQueue.main.async または Task { @MainActor } で戻す
            DispatchQueue.main.async {
                self?.isProcessing = false
                if let err = errorString {
                    self?.statusMessage = String(localized: "エラー: \(err)")
                    self?.isCapturing = false
                    self?.terminateWireshark()
                } else {
                    self?.isCapturing = true
                    let interface = self?.selectedInterface ?? ""
                    self?.statusMessage = String(localized: "キャプチャ中 (\(interface))")
                    self?.launchWireshark()
                }
            }
        }
    }
    
    // Wiresharkを起動して名前付きパイプを読み込ませる
    private func launchWireshark() {
        terminateWireshark()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Wireshark.app/Contents/MacOS/Wireshark")
        process.arguments = ["-i", outputPipePath, "-k"]
        
        // Wiresharkが終了したときのハンドラ
        process.terminationHandler = { [weak self] _ in
            print("Wiresharkが終了しました")
            // メインスレッドで安全に状態更新とキャプチャ停止処理を叩く
            DispatchQueue.main.async {
                if self?.isCapturing == true {
                    self?.stopCapture()
                }
            }
        }
        
        do {
            try process.run()
            self.wiresharkProcess = process
            print("Wiresharkを起動しました（パイプ: \(outputPipePath)）")
        } catch {
            print("Wiresharkの起動に失敗しました: \(error.localizedDescription)")
            statusMessage = "Wiresharkの起動に失敗しました。パスを確認してください。"
            stopCapture()
        }
    }
    
    // キャプチャの停止
    func stopCapture() {
        guard !isProcessing else { return }
        
        statusMessage = String(localized: "停止中...")
        isProcessing = true
        
        guard let helper = connection?.remoteObjectProxy as? WiFiCaptureHelperProtocol else {
            isCapturing = false
            isProcessing = false
            statusMessage = String(localized: "待機中")
            terminateWireshark()
            return
        }
        
        helper.stopCapture { [weak self] errorString in
            DispatchQueue.main.async {
                // 先に isCapturing を false にすることで、後の handleXPCError での
                // メッセージ上書きを防ぐ
                self?.isCapturing = false
                self?.isProcessing = false
                if let errorString = errorString {
                    self?.statusMessage = String(localized: "エラー: \(errorString)")
                } else {
                    self?.statusMessage = String(localized: "待機中")
                }
                self?.terminateWireshark()
            }
        }
    }
    
    private func terminateWireshark() {
        if let process = wiresharkProcess, process.isRunning {
            process.terminationHandler = nil // 重複トリガーを防ぐためnilを入れる
            process.terminate()
        }
        wiresharkProcess = nil
    }
}
