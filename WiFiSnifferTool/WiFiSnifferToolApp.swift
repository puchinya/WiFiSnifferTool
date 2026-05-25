//
//  WiFiSnifferToolApp.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/20.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if MainViewModel.shared.isCapturing {
            // アプリを手前に引き出してアクティブ化する
            NSApp.activate(ignoringOtherApps: true)
            
            let alert = NSAlert()
            alert.messageText = String(localized: "キャプチャを停止しますか？")
            alert.informativeText = String(localized: "現在キャプチャが実行中です。アプリを終了するとキャプチャが停止します。本当に終了しますか？")
            alert.addButton(withTitle: String(localized: "終了する"))
            alert.addButton(withTitle: String(localized: "キャンセル"))
            alert.alertStyle = .warning
            
            // ダイアログウィンドウのレベルを statusBar に設定し、MenuBarExtra（トレイウィンドウ）の最前面に表示されるようにする
            alert.window.level = .statusBar
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                MainViewModel.shared.executeImmediateCleanup()
                return .terminateNow
            } else {
                return .terminateCancel
            }
        }
        return .terminateNow
    }
}

@main
struct WiFiSnifferToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("WiFi Sniffer", image: "wifi-sniffer") {
            MainView()
        }
        .menuBarExtraStyle(.window)
    }
}
