//
//  WiFiCaptureProtocol.swift
//  WiFiSnifferTool
//
//  Created by 鍋島雅貴 on 2026/05/20.
//

import Foundation

// メインアプリからHelper Toolへ送信するコマンドの定義
@objc protocol WiFiCaptureHelperProtocol {
    
    /// キャプチャを開始する
    /// - Parameters:
    ///   - interfaceName: インターフェース名 (通常は "en0")
    ///   - channel: Wi-Fiチャンネル (例: 36, 1)
    ///   - width: チャンネル幅 (例: 20, 40, 80, 160)
    ///   - outputNamedPipe: キャプチャしたWiFiパケットの出力先となる名前付きパイプ
    ///   - completion: 処理結果を返すコールバック
    func startCapture(onInterface interfaceName: String, channel: Int, width: Int, outputNamedPipe: String, withReply completion: @escaping (String?) -> Void)
    
    /// キャプチャを停止する
    func stopCapture(withReply completion: @escaping (String?) -> Void)
}

