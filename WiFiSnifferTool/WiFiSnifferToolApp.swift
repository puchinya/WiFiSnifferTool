//
//  WiFiSnifferToolApp.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/20.
//

import SwiftUI

@main
struct WiFiSnifferToolApp: App {
    var body: some Scene {
        MenuBarExtra("WiFi Sniffer", image: "wifi-sniffer") {
            MainView()
        }
        .menuBarExtraStyle(.window)
    }
}
