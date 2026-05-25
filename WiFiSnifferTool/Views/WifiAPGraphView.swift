//
//  WifiAPGraphView.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/25.
//

import SwiftUI
import Charts

struct WifiAPGraphView: View {
    let accessPoints: [WifiAPListViewModel.AccessPoint]
    
    @State private var selectedBand = "5 GHz"
    
    struct GraphPoint: Identifiable {
        let id = UUID()
        let ssid: String
        let bssid: String
        let channel: Double
        let rssi: Double
        let originalRSSI: Int
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // バンド切り替えコントロール
            HStack {
                Text("周波数帯フィルター:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("周波数帯:", selection: $selectedBand) {
                    Text("2.4 GHz").tag("2.4 GHz")
                    Text("5 GHz").tag("5 GHz")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
                
                Spacer()
                
                Text("📊 波形は各アクセスポイントのチャンネル使用状況を示します")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // グラフ本体
            ZStack {
                if filteredAccessPoints.isEmpty {
                    emptyGraphView
                } else {
                    chartView
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // 対象バンドのアクセスポイントのフィルタリング
    private var filteredAccessPoints: [WifiAPListViewModel.AccessPoint] {
        accessPoints.filter { $0.band == selectedBand }
    }
    
    // 各アクセスポイントの頂点（中心）ポイントだけを抽出した配列（SSIDアノテーション表示用）
    private var peakPoints: [GraphPoint] {
        var points: [GraphPoint] = []
        let allAPs = filteredAccessPoints
        for ap in allAPs {
            let channel = Double(ap.channel)
            let rssi = Double(ap.rssi)
            points.append(GraphPoint(
                ssid: ap.ssid,
                bssid: ap.bssid,
                channel: channel,
                rssi: rssi,
                originalRSSI: ap.rssi
            ))
        }
        return points
    }
    
    // グラフビューの本体
    private var chartView: some View {
        Chart {
            ForEach(filteredAccessPoints) { ap in
                let points = generateDomePoints(for: ap)
                
                // ドームの中身を半透明で塗りつぶす (AreaMark)
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Channel", point.channel),
                        yStart: .value("Min RSSI", -100.0),
                        yEnd: .value("RSSI (dBm)", point.rssi)
                    )
                }
                .foregroundStyle(colorForSSID(ap.ssid, bssid: ap.bssid).opacity(0.2))
                
                // なめらかな円ドーム境界線を描画 (LineMark)
                ForEach(points) { point in
                    LineMark(
                        x: .value("Channel", point.channel),
                        y: .value("RSSI (dBm)", point.rssi)
                    )
                }
                .foregroundStyle(colorForSSID(ap.ssid, bssid: ap.bssid))
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            
            // SSID名のアノテーションラベルを追加（頂点にのみ配置）
            ForEach(peakPoints) { peak in
                PointMark(
                    x: .value("Channel", peak.channel),
                    y: .value("RSSI (dBm)", peak.rssi)
                )
                .symbolSize(0) // ドット自体は非表示にしてすっきりさせる
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text(peak.ssid)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(colorForSSID(peak.ssid, bssid: peak.bssid))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
                        .cornerRadius(4)
                        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                }
            }
        }
        .chartXScale(domain: xAxisDomain)
        .chartYScale(domain: -100 ... -30)
        .chartXAxis {
            AxisMarks(values: xAxisTicks) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisTick()
                AxisValueLabel {
                    if let ch = value.as(Double.self) {
                        Text("\(Int(ch))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-100, -90, -80, -70, -60, -50, -40, -30]) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisTick()
                AxisValueLabel {
                    if let rssi = value.as(Int.self) {
                        Text("\(rssi) dBm")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
        }
        .padding(20)
    }
    
    // 空表示
    private var emptyGraphView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("\(selectedBand) 帯のアクセスポイントが見つかりません")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("スキャンを実行するか、他の周波数帯を選択してください。")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
    
    // X軸の表示ドメイン範囲をバンドごとに決定
    private var xAxisDomain: ClosedRange<Double> {
        if selectedBand == "2.4 GHz" {
            return 0...14
        } else {
            // 5GHz: スキャンのたびにスケールが変わってガタガタ動かないよう、固定範囲 (30...170) にします
            return 30...170
        }
    }
    
    // X軸の目盛り（Tick）を決定
    private var xAxisTicks: [Double] {
        if selectedBand == "2.4 GHz" {
            return Array(1...13).map { Double($0) }
        } else {
            // 5GHz: スキャンのたびに目盛りの増減で軸幅が変動しないよう、代表的な主要チャンネルに固定します
            return [36, 48, 52, 64, 100, 116, 132, 144, 149, 165]
        }
    }
    
    // 1つのアクセスポイントに対して滑らかな円（ドームコサイン二乗波）の31個のプロットポイントを動的展開
    private func generateDomePoints(for ap: WifiAPListViewModel.AccessPoint) -> [GraphPoint] {
        let channel = Double(ap.channel)
        let rssi = Double(ap.rssi)
        
        let widthStr = ap.width.replacingOccurrences(of: " MHz", with: "")
        let width = Double(widthStr) ?? 20.0
        let spread = width / 10.0
        
        let minRssi: Double = -100.0 // 電波強度の底（グラフの下限）
        let height = rssi - minRssi
        
        var points: [GraphPoint] = []
        let steps = 30 // 30ステップ（31点）に増やして、より高精細で綺麗なカーブを構成
        
        for i in 0...steps {
            let fraction = Double(i) / Double(steps) // 0.0 ... 1.0
            let t = fraction * 2.0 - 1.0 // -1.0 ... 1.0
            let x = channel + t * spread
            
            // コサイン二乗波（ハニング窓形状）を用いて、頂点も裾野（床への接地点）も非常になめらかな美しいベル型ドームを構成
            let cosValue = cos(t * Double.pi / 2.0)
            let domeValue = cosValue * cosValue
            let y = minRssi + height * domeValue
            
            points.append(GraphPoint(
                ssid: ap.ssid,
                bssid: ap.bssid,
                channel: x,
                rssi: y,
                originalRSSI: ap.rssi
            ))
        }
        
        return points
    }
    
    // SSID と BSSID から一意なパステル調カラーを決定論的に生成
    private func colorForSSID(_ ssid: String, bssid: String) -> Color {
        let combinedString = ssid + bssid
        // FNV-1a 32-bit ハッシュを使用して決定論的なハッシュ値を生成（String.hashValueのプロセス間ランダム化による色変化を防ぐ）
        var hash: UInt32 = 2166136261
        for byte in combinedString.utf8 {
            hash = hash ^ UInt32(byte)
            hash = hash &* 16777619
        }
        let h = Double(hash % 360) / 360.0
        let s = 0.55 // パステル調のために彩度を適度に抑える
        let v = 0.90 // 明るさを高めにする
        return Color(hue: h, saturation: s, brightness: v)
    }
}

#Preview {
    WifiAPGraphView(accessPoints: [
        WifiAPListViewModel.AccessPoint(id: "1", ssid: "Test-2.4G-A", bssid: "00:11:22:33:44:55", rssi: -55, band: "2.4 GHz", channel: 6, width: "20 MHz", security: "WPA2"),
        WifiAPListViewModel.AccessPoint(id: "2", ssid: "Test-2.4G-B", bssid: "00:11:22:33:44:66", rssi: -65, band: "2.4 GHz", channel: 8, width: "40 MHz", security: "WPA3"),
        WifiAPListViewModel.AccessPoint(id: "3", ssid: "Test-5G-A", bssid: "00:11:22:33:44:77", rssi: -45, band: "5 GHz", channel: 36, width: "80 MHz", security: "WPA2")
    ])
}
