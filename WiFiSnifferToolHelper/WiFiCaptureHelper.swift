//
//  WiFiCaptureHelper.swift
//  WiFiSnifferTool
//
//  Created by 鍋島雅貴 on 2026/05/20.
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
    private var pcapHandle: OpaquePointer?
    
    // 1. キャプチャ開始
    func startCapture(onInterface interfaceName: String, channel: Int, width: Int,
                      outputNamedPipe: String, withReply completion: @escaping (String?) -> Void) {
        if isCapturing {
            completion("エラー: 既にキャプチャは開始されています。")
            return
        }
        
        // チャンネル設定を試行
        do {
            try setChannel(interfaceName: interfaceName, channel: channel, width: width)
        } catch {
            completion("チャンネル設定に失敗しました: \(error.localizedDescription)")
            return
        }
        
        isCapturing = true
        currentInterface = interfaceName
        
        // バックグラウンドスレッド等で pcap_open_live / pcap_loop などを実行
        DispatchQueue.global(qos: .userInitiated).async {
            self.runCaptureEngine(interface: interfaceName, pipePath: outputNamedPipe)
        }
        
        completion(nil)
    }
    
    private func setChannel(interfaceName: String, channel: Int, width: Int) throws {
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else {
            throw NSError(domain: "WiFiCaptureHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "インターフェースが見つかりません: \(interfaceName)"])
        }
        
        // Apple Silicon等でモニターモードを正常に動作させるため、現在のネットワークから切断する
        interface.disassociate()
        
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
        
        guard let targetChannel = supportedChannels.first(where: { $0.channelNumber == channel && (width == 0 || $0.channelWidth == targetWidth) }) else {
            throw NSError(domain: "WiFiCaptureHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "指定されたチャンネル(\(channel))または幅(\(width)MHz)はサポートされていません。"])
        }
        
        try interface.setWLANChannel(targetChannel)
    }
    
    // 2. キャプチャ停止
    func stopCapture(withReply completion: @escaping (String?) -> Void) {
        if !isCapturing {
            completion("エラー: キャプチャは動いていません。")
            return
        }
        
        print("キャプチャを停止中...")
        isCapturing = false
        
        if let handle = pcapHandle {
            pcap_breakloop(handle)
        }
        
        completion(nil)
    }
    
    // 内部のキャプチャ処理ループ
    private func runCaptureEngine(interface: String, pipePath: String) {
        // 名前付きパイプを作成
        pipePath.withCString { unlink($0) }
        let mkfifoResult = pipePath.withCString { mkfifo($0, 0o666) }
        if mkfifoResult != 0 {
            print("警告: 名前付きパイプの作成に失敗しました (すでに存在する可能性があります)")
        }
        
        let errbuf = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer { errbuf.deallocate() }
        
        guard let handle = pcap_create(interface, errbuf) else {
            let errorMsg = String(cString: errbuf)
            print("pcap_create に失敗しました: \(errorMsg)")
            isCapturing = false
            return
        }
        self.pcapHandle = handle
        
        // モニターモードを有効にする (これが Wi-Fi スニッフィングの肝)
        pcap_set_rfmon(handle, 1)
        pcap_set_snaplen(handle, 65535)
        pcap_set_timeout(handle, 100) // 100msごとにタイムアウトしてループを確認
        
        let status = pcap_activate(handle)
        if status != 0 {
            print("pcap_activate に失敗しました (ステータス: \(status))")
            pcap_close(handle)
            self.pcapHandle = nil
            isCapturing = false
            return
        }
        
        // Apple Silicon等でRadiotapヘッダを確実に取得するため、データリンク層をIEEE802_11_RADIO (127) に設定
        let DLT_IEEE802_11_RADIO: Int32 = 127
        if pcap_set_datalink(handle, DLT_IEEE802_11_RADIO) != 0 {
            print("警告: pcap_set_datalink で IEEE802_11_RADIO への設定に失敗しました")
        }
        
        print("キャプチャエンジンが開始されました (Interface: \(interface))")
        print("名前付きパイプ \(pipePath) の読み取りを待機中...")
        
        // pcap_dump_openは読み取り側（Wiresharkやメインアプリ等）が開くまでブロックする可能性があります
        guard let dumpHandle = pipePath.withCString({ pcap_dump_open(handle, $0) }) else {
            print("pcap_dump_open に失敗しました。パイプが開けません。")
            pcap_close(handle)
            self.pcapHandle = nil
            isCapturing = false
            return
        }
        
        var pktHeader: OpaquePointer?
        var pktData: UnsafePointer<UInt8>?
        
        while isCapturing {
            let res = pcap_next_ex(handle, &pktHeader, &pktData)
            if res == 1, let header = pktHeader, let data = pktData {
                // パケット取得成功、パイプにダンプ
                pcap_dump(dumpHandle, header, data)
                pcap_dump_flush(dumpHandle)
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
