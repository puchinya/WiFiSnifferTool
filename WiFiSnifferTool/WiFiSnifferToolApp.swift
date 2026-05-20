//
//  WiFiSnifferToolApp.swift
//  WiFiSnifferTool
//
//  Created by 鍋島雅貴 on 2026/05/20.
//

import SwiftUI

@main
struct WiFiSnifferToolApp: App {
    var body: some Scene {
        MenuBarExtra("WiFi Sniffer", systemImage: "wifi.viewfinder") {
            MainView()
        }
        .menuBarExtraStyle(.window)
    }
}
