//
//  WiFiCaptureHelper.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/20.
//

import Foundation
import CoreWLAN // チャンネル変更等に使用
import Darwin   // mkfifoなどに使用

// libpcap の C 関数を Swift から呼び出すための定義
@_silgen_name("pcap_create")
func pcap_create(_ device: UnsafePointer<Int8>, _ errbuf: UnsafeMutablePointer<Int8>) -> OpaquePointer?

@_silgen_name("pcap_set_rfmon")
func pcap_set_rfmon(_ p: OpaquePointer, _ rfmon: Int32) -> Int32

@_silgen_name("pcap_set_snaplen")
func pcap_set_snaplen(_ p: OpaquePointer, _ snaplen: Int32) -> Int32

@_silgen_name("pcap_set_timeout")
func pcap_set_timeout(_ p: OpaquePointer, _ timeout: Int32) -> Int32

@_silgen_name("pcap_activate")
func pcap_activate(_ p: OpaquePointer) -> Int32

@_silgen_name("pcap_close")
func pcap_close(_ p: OpaquePointer)

@_silgen_name("pcap_next_ex")
func pcap_next_ex(_ p: OpaquePointer, _ pkt_header: UnsafeMutablePointer<OpaquePointer?>, _ pkt_data: UnsafeMutablePointer<UnsafePointer<UInt8>?>) -> Int32

@_silgen_name("pcap_breakloop")
func pcap_breakloop(_ p: OpaquePointer)

@_silgen_name("pcap_set_datalink")
func pcap_set_datalink(_ p: OpaquePointer, _ dlt: Int32) -> Int32

@_silgen_name("pcap_dump_open")
func pcap_dump_open(_ p: OpaquePointer, _ fname: UnsafePointer<Int8>) -> OpaquePointer?

@_silgen_name("pcap_dump")
func pcap_dump(_ user: OpaquePointer, _ h: OpaquePointer, _ sp: UnsafePointer<UInt8>)

@_silgen_name("pcap_dump_close")
func pcap_dump_close(_ p: OpaquePointer)

@_silgen_name("pcap_dump_flush")
func pcap_dump_flush(_ p: OpaquePointer) -> Int32

class WiFiCaptureHelper: NSObject, WiFiCaptureHelperProtocol {
    
    private var isCapturing = false
    private var currentInterface: String?
    private var currentPipePath: String?
    private var pcapHandle: OpaquePointer?
    private var activeInterface: CWInterface? // 同一インスタンスを一貫保持するために追加
    
    // 1. キャプチャ開始
    func startCapture(onInterface interfaceName: String, channel: Int, width: Int,
                      outputNamedPipe: String, withReply completion: @escaping (String?) -> Void) {
        if isCapturing {
            completion("エラー: 既にキャプチャは開始されています。")
            return
        }
        
        // パイプファイルをヘルパー側で同期的に再作成 (古いものがあれば削除して新規作成)
        _ = outputNamedPipe.withCString { unlink($0) }
        let mkfifoResult = outputNamedPipe.withCString { mkfifo($0, 0o666) }
        if mkfifoResult != 0 {
            print("警告: ヘルパー側での名前付きパイプ作成に失敗しました (すでに存在する可能性があります)")
        } else {
            print("ヘルパー側で名前付きパイプを新規作成しました: \(outputNamedPipe)")
        }
        
        // 【最重要 1】一貫操作のため、同一の CWInterface インスタンスを取得
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else {
            completion("エラー: インターフェースが見つかりません: \(interfaceName)")
            return
        }
        self.activeInterface = interface
        
        // 【究極シーケンス 1】pcap_activate の前にアソシエーションを切断し、1回目のチャンネル設定を行う
        // 接続状態でのアクティベート拒否を防ぎつつ、初期周波数をアライメント
        interface.disassociate()
        print("[1] アソシエーションを解除（disassociate）しました。")
        Thread.sleep(forTimeInterval: 0.2) // 切断ステート反映のためのウェイト
        
        do {
            try setChannel(interface: interface, channel: channel, width: width)
            print("[2] アクティベート前の初期チャンネル設定（1回目）に成功しました。")
        } catch {
            print("警告: アクティベート前のチャンネル設定に失敗しました: \(error.localizedDescription)")
            // 後続のアクティベート後の設定でカバーできる可能性があるため続行
        }
        
        // チャンネル切り替え後のハードウェア安定化を待つため、しっかりとスリープ（500ms）
        Thread.sleep(forTimeInterval: 0.5)
        
        // 【究極シーケンス 2】pcap の作成とモニターモードの有効化
        let errbuf = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer { errbuf.deallocate() }
        
        guard let handle = pcap_create(interfaceName, errbuf) else {
            let errorMsg = String(cString: errbuf)
            completion("pcap_create に失敗しました: \(errorMsg)")
            return
        }
        
        // モニターモードを有効にする (これが Wi-Fi スニッフィングの肝)
        _ = pcap_set_rfmon(handle, 1)
        _ = pcap_set_snaplen(handle, 65535)
        _ = pcap_set_timeout(handle, 100) // 100msごとにタイムアウトしてループを確認
        
        let status = pcap_activate(handle)
        if status != 0 {
            pcap_close(handle)
            completion("pcap_activate に失敗しました (ステータス: \(status))")
            return
        }
        print("[3] pcapモニターモードのアクティベートが成功しました。")
        
        // モニターモード移行のハードウェア受信状態移行を待つ（300ms）
        Thread.sleep(forTimeInterval: 0.3)
        
        // 【究極シーケンス 3】モニターモード状態で、再度念押しのチャンネル設定（2回目）を行う
        // アクティベート時の暗黙のチャンネルリセットや無視を完全に上書き
        do {
            try setChannel(interface: interface, channel: channel, width: width)
            print("[4] アクティベート後の念押しチャンネル設定（2回目）に成功しました。")
        } catch {
            pcap_close(handle)
            completion("チャンネル設定に失敗しました: \(error.localizedDescription)")
            return
        }
        
        // チャンネルロック完了とハードウェアチューニングの安定化のためスリープ（500ms）
        Thread.sleep(forTimeInterval: 0.5)
        
        // 【究極シーケンス 4】反映確認＆リトライループ (最大3回リトライ)
        var isVerified = false
        for attempt in 1...3 {
            if let currentWlanChannel = interface.wlanChannel(), currentWlanChannel.channelNumber == channel {
                isVerified = true
                let currentWidthStr: String
                switch currentWlanChannel.channelWidth {
                case .width20MHz: currentWidthStr = "20 MHz"
                case .width40MHz: currentWidthStr = "40 MHz"
                case .width80MHz: currentWidthStr = "80 MHz"
                case .width160MHz: currentWidthStr = "160 MHz"
                default: currentWidthStr = "Unknown"
                }
                print("--- [成功] 物理チャンネルの反映を確認 ---")
                print("  - 試行回数: \(attempt) 回目")
                print("  - 確定物理チャンネル: \(currentWlanChannel.channelNumber)")
                print("  - 確定物理チャンネル幅: \(currentWidthStr)")
                print("-----------------------------------------")
                break
            } else {
                print("警告: チャンネル設定がまだ反映されていません (試行: \(attempt) 回目)。再設定を行います。")
                // 再適用を試行
                _ = try? setChannel(interface: interface, channel: channel, width: width)
                Thread.sleep(forTimeInterval: 0.2) // リトライ時の適用ウェイト
            }
        }
        
        if !isVerified {
            print("警告: 最大回数リトライしましたが、システム側での最終反映が確認できませんでした。スニッフは続行します。")
        }
        
        // Radiotapヘッダを確実に取得するため、データリンク層を設定
        let DLT_IEEE802_11_RADIO: Int32 = 127
        if pcap_set_datalink(handle, DLT_IEEE802_11_RADIO) != 0 {
            print("警告: pcap_set_datalink で IEEE802_11_RADIO への設定に失敗しました")
        }
        
        self.pcapHandle = handle
        isCapturing = true
        currentInterface = interfaceName
        currentPipePath = outputNamedPipe
        
        // バックグラウンドスレッドで pcap_next_ex によるダンプループを実行
        DispatchQueue.global(qos: .userInitiated).async {
            self.runCaptureEngine(handle: handle, pipePath: outputNamedPipe)
        }
        
        completion(nil)
    }
    
    private func setChannel(interface: CWInterface, channel: Int, width: Int) throws {
        // 利用可能なチャンネルを検索
        guard let supportedChannels = interface.supportedWLANChannels() else {
            throw NSError(domain: "WiFiCaptureHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "サポートされているチャンネルを取得できません。"])
        }
        
        let targetWidth: CWChannelWidth
        switch width {
        case 20: targetWidth = .width20MHz
        case 40: targetWidth = .width40MHz
        case 80: targetWidth = .width80MHz
        case 160: targetWidth = .width160MHz
        default: targetWidth = .widthUnknown
        }
        
        // チャンネル番号から周波数帯（Band）を自動判定 (14以下は2.4GHz、それ以上は5GHz)
        let expectedBand: CWChannelBand = channel <= 14 ? .band2GHz : .band5GHz
        
        // 1. 指定のチャンネル番号、帯域(Band)、および幅(Width)がすべて一致するものを探す
        var targetChannel = supportedChannels.first(where: {
            $0.channelNumber == channel &&
            $0.channelBand == expectedBand &&
            (width == 0 || $0.channelWidth == targetWidth)
        })
        
        // 2. 見つからない場合は、指定のチャンネル番号と帯域(Band)が一致するもので、幅は不問として最初の候補を選ぶ (フォールバック)
        if targetChannel == nil {
            targetChannel = supportedChannels.first(where: {
                $0.channelNumber == channel &&
                $0.channelBand == expectedBand
            })
            if let tc = targetChannel {
                print("フォールバック: チャンネル \(channel) の指定幅(\(width)MHz)が見つからないため、幅 \(tc.channelWidth) で代替します。")
            }
        }
        
        // 3. それでも見つからない場合は、幅も帯域も不問でチャンネル番号だけで探す (最終フォールバック)
        if targetChannel == nil {
            targetChannel = supportedChannels.first(where: {
                $0.channelNumber == channel
            })
        }
        
        guard let finalChannel = targetChannel else {
            throw NSError(domain: "WiFiCaptureHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "指定されたチャンネル(\(channel))はサポートされていません。"])
        }
        
        try interface.setWLANChannel(finalChannel)
    }
    
    // 2. キャプチャ停止
    func stopCapture(withReply completion: @escaping (String?) -> Void) {
        if !isCapturing {
            completion("エラー: キャプチャは動いていません。")
            return
        }
        
        print("キャプチャを停止中...")
        isCapturing = false
        
        // pcap_dump_open がパイプのオープン待ちでブロックしている可能性があるため、
        // ダミーでオープンしてブロックを強制解除する
        if let pipePath = currentPipePath {
            DispatchQueue.global().async {
                let fd = open(pipePath, O_RDONLY | O_NONBLOCK)
                if fd != -1 {
                    close(fd)
                }
            }
        }
        
        if let handle = pcapHandle {
            pcap_breakloop(handle)
        }
        
        completion(nil)
    }
    
    // 内部のキャプチャ処理ループ
    private func runCaptureEngine(handle: OpaquePointer, pipePath: String) {
        print("キャプチャエンジンが開始されました")
        print("名前付きパイプ \(pipePath) の読み取りを待機中...")
        
        // pcap_dump_openは読み取り側（Wireshark等）が開くまでブロックする可能性があります
        guard let dumpHandle = pipePath.withCString({ pcap_dump_open(handle, $0) }) else {
            print("pcap_dump_open に失敗しました。パイプが開けません。")
            pcap_close(handle)
            self.pcapHandle = nil
            isCapturing = false
            return
        }
        
        print("Wiresharkがパイプを開きました。キャプチャループを開始します。")
        
        var pktHeader: OpaquePointer?
        var pktData: UnsafePointer<UInt8>?
        
        while isCapturing {
            let res = pcap_next_ex(handle, &pktHeader, &pktData)
            if res == 1, let header = pktHeader, let data = pktData {
                // パケット取得成功、パイプにダンプ
                pcap_dump(dumpHandle, header, data)
                _ = pcap_dump_flush(dumpHandle)
            } else if res == 0 {
                // タイムアウト
                continue
            } else {
                // エラーまたはループ終了
                break
            }
        }
        
        pcap_dump_close(dumpHandle)
        pcap_close(handle)
        self.pcapHandle = nil
        isCapturing = false
        print("キャプチャエンジンが停止しました。")
    }
}
