//
//  main.swift
//  WiFiSnifferToolHelper
//
//  Created by 鍋島雅貴 on 2026/05/20.
//

import Foundation

/// XPC接続を受け入れるためのデリゲートクラス
class XcodeHelperDelegate: NSObject, NSXPCListenerDelegate {
    
    // メインアプリがXPCで接続してきたときに呼び出されるメソッド
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        
        // 1. メインアプリが呼び出していいプロトコル（インターフェース）を登録
        let exportedInterface = NSXPCInterface(with: WiFiCaptureHelperProtocol.self)
        newConnection.exportedInterface = exportedInterface
        
        // 2. 最初に作成した、実際のWi-Fiキャプチャロジックを持つクラスのインスタンスを生成して割り当て
        let helperObject = WiFiCaptureHelper()
        newConnection.exportedObject = helperObject
        
        // 3. 【セキュリティ（重要）】
        // 接続してきたアプリが「本当に自分のメインアプリか」を検証します。
        // 本番環境では SecCode を使用して Team ID や署名を厳密にチェックする必要があります。
        // ここでは、最低限のチェックとして、同一プロセスまたはデバッグ中の接続を許可するイメージです。
        /*
        let code: SecCode? = nil
        // SecCodeCopyGuestWithAttributes などを使用して検証ロジックを実装します
        */
        
        // 4. 接続を許可してスタート
        newConnection.resume()
        return true
    }
}

// ==========================================
// エントリーポイント（プログラムの開始位置）
// ==========================================

// 1. ヘルパーのMachサービス名（識別子）を定義
// ※のちほど作成する Launchd.plist の「MachServices」に書く文字列と完全に一致させる必要があります。
let helperMachServiceName = "jp.daradara.WiFiSnifferToolHelper"

print("WiFiSnifferToolHelper: 特権デーモンを起動中...")

// 2. Machサービス名を使ってXPCリスナーを初期化
let listener = NSXPCListener(machServiceName: helperMachServiceName)

// 3. デリゲートをセットして、接続待ち受けを開始
let delegate = XcodeHelperDelegate()
listener.delegate = delegate
listener.resume()

// 4. デーモンプロセスが終了しないようにメインループを維持
RunLoop.main.run()
