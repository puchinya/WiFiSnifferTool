//
//  Untitled.swift
//  WiFiSnifferTool
//
//  Created by 鍋島雅貴 on 2026/05/20.
//

import Foundation
import CoreWLAN // チャンネル変更等に使用

class WiFiCaptureHelper: NSObject, WiFiCaptureHelperProtocol {
    
    private var isCapturing = false
    private var currentInterface: String?
    
    // 1. チャンネル・周波数の設定
    func setChannel(channel: Int, width: Int, withReply completion: @escaping (String?) -> Void) {
        // キャプチャ中はチャンネル変更できないようにガードするのが安全です
        if isCapturing {
            completion("エラー: キャプチャ実行中はチャンネルを変更できません。")
            return
        }
        
        // 実際のmacOSでのWi-Fi制御ロジック
        // ※実際にはCWWiFiClientなどを用いてインターフェースを取得し、
        //   disassociate() してから ch, width を設定する処理が入ります。
        print("チャンネルを \(channel) (幅: \(width)MHz) に設定中...")
        
        // 成功時は nil を返す
        completion(nil)
    }
    
    // 2. キャプチャ開始
    func startCapture(onInterface interfaceName: String, withReply completion: @escaping (String?) -> Void) {
        if isCapturing {
            completion("エラー: 既にキャプチャは開始されています。")
            return
        }
        
        isCapturing = true
        currentInterface = interfaceName
        print("インターフェース \(interfaceName) でキャプチャを開始します。")
        
        // バックグラウンドスレッド等で pcap_open_live / pcap_loop などを実行
        DispatchQueue.global(qos: .userInitiated).async {
            self.runCaptureEngine(interface: interfaceName)
        }
        
        completion(nil)
    }
    
    // 3. キャプチャ停止
    func stopCapture(withReply completion: @escaping (String?) -> Void) {
        if !isCapturing {
            completion("エラー: キャプチャは動いていません。")
            return
        }
        
        print("キャプチャを停止中...")
        isCapturing = false
        
        // ここでpcapのループをブレイクさせる処理（pcap_breakloop等）を行う
        
        completion(nil)
    }
    
    // 内部のキャプチャ処理ループ（イメージ）
    private func runCaptureEngine(interface: String) {
        while isCapturing {
            // libpcap等を使ったパケット取得ロジック
            // 取得したパケットはファイル(pcap)に書き出すか、
            // 別途メインアプリ側のXPCプロトコルを呼び出してリアルタイム転送します
            usleep(100000) // ダミーループ用
        }
        print("キャプチャエンジンが停止しました。")
    }
}

