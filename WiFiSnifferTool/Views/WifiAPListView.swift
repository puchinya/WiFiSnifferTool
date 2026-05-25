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
    @State private var mainViewModel = MainViewModel.shared
    
    @State private var showingStopAlert = false
    @State private var targetAPForCapture: WifiAPListViewModel.AccessPoint?
    @State private var selectedTab = 0 // 0: リスト表示, 1: グラフ表示
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー部（表示形式・今すぐスキャンボタンを内包）
            headerView
            
            Divider()
            
            // 検索・フィルター・ソートバー (リスト表示のみ表示)
            if selectedTab == 0 {
                filterBar
                Divider()
            }
            
            // コンテンツ表示 (リストかグラフ)
            if selectedTab == 0 {
                contentList
            } else {
                WifiAPGraphView(accessPoints: viewModel.accessPoints)
            }
        }
        .frame(minWidth: 850, minHeight: 500) // 画面が広くなったので最小高さを580から500に最適化
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            viewModel.stopPeriodicScan()
        }
        .alert("キャプチャの停止確認", isPresented: $showingStopAlert) {
            Button("停止して開始", role: .destructive) {
                if let ap = targetAPForCapture {
                    targetAPForCapture = nil
                    Task {
                        await mainViewModel.stopCapture()
                        startCapture(for: ap)
                    }
                }
            }
            Button("キャンセル", role: .cancel) {
                targetAPForCapture = nil
            }
        } message: {
            Text("現在すでにキャプチャが実行中です。実行中のキャプチャを停止して、このアクセスポイントで新しくキャプチャを開始しますか？")
        }
    }
    
    private func handleCaptureRequest(for ap: WifiAPListViewModel.AccessPoint) {
        if mainViewModel.isCapturing {
            targetAPForCapture = ap
            showingStopAlert = true
        } else {
            startCapture(for: ap)
        }
    }
    
    private func startCapture(for ap: WifiAPListViewModel.AccessPoint) {
        let channel = ap.channel
        let widthStr = ap.width.replacingOccurrences(of: " MHz", with: "")
        let width = Int(widthStr) ?? 20
        
        mainViewModel.selectedChannel = channel
        mainViewModel.selectedChannelWidth = width
        
        Task {
            await mainViewModel.startCapture()
            if mainViewModel.isCapturing {
                APListWindowController.shared.close()
            }
        }
    }
    
    // ヘッダービュー
    private var headerView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("周辺のWiFiアクセスポイント")
                    .font(.headline)
                    .fontWeight(.bold)
                
                HStack(spacing: 8) {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("スキャン中...")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("見つかったAP: \(viewModel.filteredAccessPoints.count) 個")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    if let err = viewModel.errorMessage {
                        Text("⚠️")
                            .foregroundColor(.red)
                            .font(.caption)
                            .help(err)
                    }
                }
                .frame(height: 16) // 高さを完全に固定して、ProgressView出現時の縦揺れを防ぐ！
            }
            .frame(height: 38, alignment: .leading) // VStack全体の高さを完全に固定！
            
            Spacer()
            
            // 表示形式をヘッダーの同じ行に配置
            Picker("表示形式", selection: $selectedTab) {
                Label("リスト", systemImage: "list.bullet").tag(0)
                Label("グラフ", systemImage: "chart.bar.xaxis").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()
            
            Button(action: {
                viewModel.scan()
            }) {
                Label("今すぐスキャン", systemImage: "arrow.clockwise")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 20)
        .frame(height: 56) // ヘッダー全体の高さを完全に固定（高さの変動を一切外に伝播させない）
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
                            AccessPointRow(ap: ap, isProcessing: mainViewModel.isProcessing || mainViewModel.requiresApproval) { selectedAP in
                                handleCaptureRequest(for: selectedAP)
                            }
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
    let isProcessing: Bool
    let onStartCapture: (WifiAPListViewModel.AccessPoint) -> Void
    
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
                .frame(width: 120, alignment: .trailing)
                .layoutPriority(1)
            
            // キャプチャ開始ボタン
            Button(action: {
                onStartCapture(ap)
            }) {
                Text("キャプチャ")
                    .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isProcessing)
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
