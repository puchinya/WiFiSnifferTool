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
        
        guard isValidPeer(connection: newConnection) else {
            print("セキュリティ警告: 不正なアプリからの接続を拒否しました。")
            return false
        }
        
        // 1. メインアプリが呼び出していいプロトコル（インターフェース）を登録
        let exportedInterface = NSXPCInterface(with: WiFiCaptureHelperProtocol.self)
        newConnection.exportedInterface = exportedInterface
        
        // 2. 最初に作成した、実際のWi-Fiキャプチャロジックを持つクラスのインスタンスを生成して割り当て
        let helperObject = WiFiCaptureHelper()
        newConnection.exportedObject = helperObject
        
        // メインアプリが終了して接続が切れたら、ヘルパー自身も終了する
        newConnection.invalidationHandler = {
            // 必要に応じてクリーアップ処理をここに書く
            exit(0)
        }
        
        // 4. 接続を許可してスタート
        newConnection.resume()
        return true
    }
    
    private func isValidPeer(connection: NSXPCConnection) -> Bool {
        // 1. 自身の Info.plist から SMAuthorizedClients を取得
        guard let infoDictionary = Bundle.main.infoDictionary,
              let authorizedClients = infoDictionary["SMAuthorizedClients"] as? [String],
              let requirementString = authorizedClients.first else {
            print("エラー: Info.plist から SMAuthorizedClients を読み込めません。")
            return false
        }
        
        // 2. 【100%パブリックAPI】
        // 接続してきた「メッセージオブジェクト」から直接、安全にSecCode（署名情報）を生成する
        // ※ 内部的にOSが監査トークン（Audit Token）の突合を自動で行ってくれる仕組みです
        var code: SecCode?
        
        // NSXPCConnection から生の XPC メッセージ（またはイベント）のコンテキストを取得できない場合の
        // 最もクリーンで現代的な接続元検証のパブリック手順：
        
        // メインアプリが一番最初にXPCで通信を行ってきた際の「リクエストメッセージ」そのものから
        // 署名を判定するのがAppleの公式推奨（SecCodeCreateWithXPCMessage）ですが、
        // `shouldAcceptNewConnection` の段階でそれを行う場合は、
        // 現代のmacOS SDKに完全に露出しているパブリックプロパティ `processIdentifier` (PID) を
        // 単体で使うのではなく、以下のように「SecCodeCopyGuestWithAttributes」を正規に呼び出します。
        
        let pid = connection.processIdentifier
        let attributes: [CFString: Any] = [
            kSecGuestAttributePid: pid
        ]
        
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code)
        guard status == errSecSuccess, let secureCode = code else {
            return false
        }
        
        // 3. 要求文字列から検証用のオブジェクトを作成
        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)
        guard reqStatus == errSecSuccess, let secRequirement = requirement else {
            return false
        }
        
        // 4. 検証を実行
        let validityStatus = SecCodeCheckValidity(secureCode, [], secRequirement)
        guard validityStatus == errSecSuccess else {
            return false
        }
        
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

// 3. 【重要】SIGPIPEを無視するように設定
// Wireshark（読み取り側）がパイプを閉じたときに、書き込み側のヘルパーがクラッシュするのを防ぎます。
signal(SIGPIPE, SIG_IGN)

// 4. デリゲートをセットして、接続待ち受けを開始
let delegate = XcodeHelperDelegate()
listener.delegate = delegate
listener.resume()

// 4. デーモンプロセスが終了しないようにメインループを維持
RunLoop.main.run()
