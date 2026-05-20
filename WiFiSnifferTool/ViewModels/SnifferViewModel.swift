import SwiftUI
import CoreWLAN
import ServiceManagement

@Observable
class SnifferViewModel {
    var isCapturing: Bool = false
    var statusMessage: String = "待機中"
    
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
    
    // ヘルパーとのXPC接続
    private var connection: NSXPCConnection?
    // パイプからの読み込みタスク
    private var readTask: Task<Void, Never>?
    
    // CoreWLANクライアントから取得した生のチャンネル情報キャッシュ
    private var cachedWLANChannels: [CWChannel] = []
    
    init() {
        installHelperIfNeeded()
        fetchInterfaces()
    }
    
    private func installHelperIfNeeded() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.example.MyWiFiSnifferHelper.plist")
            if service.status == .requiresApproval {
                statusMessage = "システム設定でヘルパーの実行を許可してください"
                return
            }
            if service.status != .enabled {
                do {
                    try service.register()
                    print("ヘルパーを登録しました")
                } catch {
                    print("ヘルパーの登録に失敗しました: \(error)")
                    statusMessage = "ヘルパーツールのインストールに失敗しました"
                }
            } else {
                 print("ヘルパーは既に登録されています")
            }
        }
    }
    
    func fetchInterfaces() {
        let client = CWWiFiClient.shared()
        availableInterfaces = client.interfaces()?.compactMap { $0.interfaceName } ?? ["en0"]
        if let first = availableInterfaces.first {
            selectedInterface = first // didSetが呼ばれ、updateAvailableChannelsが実行される
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
        
        // チャンネル番号の重複を排除してソート
        let uniqueChannels = Set(cachedWLANChannels.map { $0.channelNumber })
        availableChannels = Array(uniqueChannels).sorted()
        
        // 現在選択されているチャンネルが新しいリストに含まれていなければ、最初の要素を選択
        if !availableChannels.contains(selectedChannel), let firstChannel = availableChannels.first {
            selectedChannel = firstChannel // didSetが呼ばれ、updateAvailableWidthsが実行される
        } else {
            updateAvailableWidths()
        }
    }
    
    private func updateAvailableWidths() {
        // 現在選択されているチャンネル番号に一致する CWChannel を抽出
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
        
        // 取得できない場合や未知の幅の場合はデフォルトで20を含める
        if availableWidths.isEmpty {
            availableWidths = [20]
        }
        
        // 現在選択されている幅が新しいリストに含まれていなければ、最初の要素を選択
        if !availableWidths.contains(selectedChannelWidth), let firstWidth = availableWidths.first {
            selectedChannelWidth = firstWidth
        }
    }
    
    // ヘルパーとのXPC接続を確立する
    private func setupXPCConnection() -> WiFiCaptureHelperProtocol? {
        if connection == nil {
            // ヘルパーのMachサービス名 (main.swiftで定義したものと同じ)
            let machServiceName = "com.example.MyWiFiSnifferHelper"
            connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
            
            // リモートオブジェクトが準拠するプロトコルを指定
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
            self.isCapturing = false
            self.statusMessage = "ヘルパーツールとの通信が切断されました"
            self.connection = nil
            self.stopPipeReading()
        }
    }
    
    // キャプチャの開始
    func startCapture() {
        guard let helper = setupXPCConnection() else {
            statusMessage = "ヘルパーツールに接続できません。インストールされているか確認してください。"
            return
        }
        
        statusMessage = "キャプチャを開始しています..."
        
        // 1. パイプからの読み込みを非同期で開始（pcap_dump_openのブロックを防ぐため先に開始する）
        startPipeReading()
        
        // 2. ヘルパーにキャプチャ開始を指示
        helper.startCapture(onInterface: selectedInterface,
                            channel: selectedChannel,
                            width: selectedChannelWidth,
                            outputNamedPipe: outputPipePath) { [weak self] errorString in
            Task { @MainActor in
                if let err = errorString {
                    self?.statusMessage = "エラー: \(err)"
                    self?.isCapturing = false
                    self?.stopPipeReading()
                } else {
                    self?.isCapturing = true
                    self?.statusMessage = "キャプチャ中 (\(self?.selectedInterface ?? ""))"
                }
            }
        }
    }
    
    // キャプチャの停止
    func stopCapture() {
        statusMessage = "停止中..."
        
        guard let helper = connection?.remoteObjectProxy as? WiFiCaptureHelperProtocol else {
            isCapturing = false
            statusMessage = "待機中"
            stopPipeReading()
            return
        }
        
        helper.stopCapture { [weak self] errorString in
            Task { @MainActor in
                self?.isCapturing = false
                self?.statusMessage = errorString ?? "待機中"
                self?.stopPipeReading()
            }
        }
    }
    
    // 名前付きパイプからデータを読み込む（今回はコンソールへの出力またはダミー処理）
    private func startPipeReading() {
        stopPipeReading()
        
        let pipeURL = URL(fileURLWithPath: outputPipePath)
        
        readTask = Task.detached(priority: .background) { [weak self] in
            // ヘルパーがmkfifoするまで少し待つ場合がある
            var fileHandle: FileHandle? = nil
            for _ in 0..<10 { // 最大10回リトライ (約5秒)
                if Task.isCancelled { return }
                do {
                    fileHandle = try FileHandle(forReadingFrom: pipeURL)
                    break
                } catch {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
                }
            }
            
            guard let handle = fileHandle else {
                Task { @MainActor in self?.statusMessage = "パイプの読み取りに失敗しました" }
                return
            }
            
            defer { try? handle.close() }
            print("パイプからの読み取りを開始しました: \(pipeURL.path)")
            
            // ストリーム読み込み
            do {
                for try await data in handle.bytes {
                    if Task.isCancelled { break }
                    // ここで読み取ったデータを処理（Wiresharkに流す、ファイルに保存する、GUIで解析するなど）
                    // ※ UI更新は重いため、データ処理はバックグラウンドで行うこと
                    _ = data
                }
            } catch {
                print("パイプ読み込みエラー: \(error)")
            }
            print("パイプからの読み取りが終了しました")
        }
    }
    
    private func stopPipeReading() {
        readTask?.cancel()
        readTask = nil
    }
}
