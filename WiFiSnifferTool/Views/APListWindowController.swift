//
//  APListWindowController.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/24.
//

import AppKit
import SwiftUI

class APListWindowController: NSObject, NSWindowDelegate {
    static let shared = APListWindowController()
    
    private var window: NSWindow?
    
    func show() {
        // すでにウィンドウが存在する場合は前面に表示
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 新しくウィンドウを作成
        let contentView = WifiAPListView()
        let hostingView = NSHostingView(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = String(localized: "周辺のWiFiアクセスポイント")
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.setFrameAutosaveName("WifiAPListWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
    }
    
    // ウィンドウが閉じられる時のデリゲート
    func windowWillClose(_ notification: Notification) {
        // 参照を nil にしてメモリ解放 (ViewModel内のタイマー等も deinit されます)
        self.window = nil
    }
}
