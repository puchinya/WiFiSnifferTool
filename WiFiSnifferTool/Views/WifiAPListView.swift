//
//  WifiAPListView.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/24.
//

import SwiftUI
import CoreWLAN

struct WifiAPListView: View {
    @State private var viewModel = WifiAPListViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー部
            headerView
            
            // 検索・フィルター・ソートバー
            filterBar
            
            Divider()
            
            // アクセスポイント一覧
            contentList
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            viewModel.stopPeriodicScan()
        }
    }
    
    // ヘッダービュー
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("周辺のWiFiアクセスポイント")
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 12) {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("周辺のWi-Fiをスキャン中...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("見つかったAP: \(viewModel.filteredAccessPoints.count) 個")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    
                    if let err = viewModel.errorMessage {
                        Text("⚠️ \(err)")
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                viewModel.scan()
            }) {
                Label("今すぐスキャン", systemImage: "arrow.clockwise")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // 検索・フィルタリング・ソートコントロール
    private var filterBar: some View {
        HStack(spacing: 15) {
            // 検索ボックス
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("SSID または BSSID で検索...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(width: 250)
            
            Spacer()
            
            // 周波数帯フィルター
            Picker("周波数帯:", selection: $viewModel.selectedBandFilter) {
                Text("すべて").tag("All")
                Text("2.4 GHz").tag("2.4 GHz")
                Text("5 GHz").tag("5 GHz")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .labelsHidden()
            
            // ソート
            Picker("ソート:", selection: $viewModel.selectedSortOption) {
                Label("電波強度", systemImage: "wifi").tag("RSSI")
                Label("SSID順", systemImage: "textformat").tag("SSID")
                Label("チャンネル", systemImage: "number").tag("Channel")
            }
            .frame(width: 180)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    // リストコンテンツ
    private var contentList: some View {
        VStack {
            if viewModel.filteredAccessPoints.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredAccessPoints) { ap in
                            AccessPointRow(ap: ap)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    // 空白時の表示
    private var emptyStateView: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.7))
            
            Text("アクセスポイントが見つかりません")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("位置情報サービスがオンになっており、アプリに権限が与えられていることを確認してください。また、Wi-Fiが有効になっている必要があります。")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 450)
            
            Button(action: {
                viewModel.scan()
            }) {
                Text("再試行")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}

// 1つのアクセスポイントを表示する行ビュー
struct AccessPointRow: View {
    let ap: WifiAPListViewModel.AccessPoint
    
    var body: some View {
        HStack(spacing: 15) {
            // 電波強度表示
            VStack(spacing: 4) {
                SignalIndicator(level: ap.signalLevel, rssi: ap.rssi)
                Text("\(ap.rssi) dBm")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(rssiColor(ap.rssi))
            }
            .frame(width: 60)
            
            // SSID & BSSID
            VStack(alignment: .leading, spacing: 4) {
                Text(ap.ssid)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(ap.bssid)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 周波数帯 (Band)
            Text(ap.band)
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(bandBgColor(ap.band))
                .foregroundColor(bandTextColor(ap.band))
                .cornerRadius(6)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            
            // チャンネル & チャンネル幅
            VStack(alignment: .trailing, spacing: 3) {
                Text("Ch \(ap.channel)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(ap.width)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .trailing)
            .layoutPriority(1)
            
            // 暗号設定 (Security)
            SecurityBadge(security: ap.security)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 140, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -65 { return .teal }
        if rssi >= -80 { return .yellow }
        if rssi >= -90 { return .orange }
        return .red
    }
    
    private func bandBgColor(_ band: String) -> Color {
        if band == "2.4 GHz" {
            return Color.blue.opacity(0.15)
        } else if band == "5 GHz" {
            return Color.green.opacity(0.15)
        }
        return Color.secondary.opacity(0.15)
    }
    
    private func bandTextColor(_ band: String) -> Color {
        if band == "2.4 GHz" {
            return Color.blue
        } else if band == "5 GHz" {
            return Color.green
        }
        return Color.primary
    }
}

// カスタム信号強度バーインジケータ
struct SignalIndicator: View {
    let level: Int
    let rssi: Int
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < level ? barColor(for: level) : Color.secondary.opacity(0.2))
                    .frame(width: 4, height: CGFloat(index + 1) * 4)
            }
        }
    }
    
    private func barColor(for level: Int) -> Color {
        switch level {
        case 4: return .green
        case 3: return .teal
        case 2: return .yellow
        case 1: return .orange
        default: return .red
        }
    }
}

// セキュリティ設定バッジ
struct SecurityBadge: View {
    let security: String
    
    var body: some View {
        Text(security)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeBgColor(security))
            .foregroundColor(badgeTextColor(security))
            .cornerRadius(6)
            .lineLimit(1)
    }
    
    private func badgeBgColor(_ security: String) -> Color {
        if security.localizedCaseInsensitiveContains("Open") {
            return Color.red.opacity(0.15)
        } else if security.localizedCaseInsensitiveContains("WPA3") {
            return Color.purple.opacity(0.15)
        } else if security.localizedCaseInsensitiveContains("WPA2") {
            return Color.orange.opacity(0.15)
        }
        return Color.secondary.opacity(0.15)
    }
    
    private func badgeTextColor(_ security: String) -> Color {
        if security.localizedCaseInsensitiveContains("Open") {
            return Color.red
        } else if security.localizedCaseInsensitiveContains("WPA3") {
            return Color.purple
        } else if security.localizedCaseInsensitiveContains("WPA2") {
            return Color.orange
        }
        return Color.primary
    }
}

#Preview {
    WifiAPListView()
}
