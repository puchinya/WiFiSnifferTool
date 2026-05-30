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
        var labelPosition: AnnotationPosition = .top
        var labelOffsetY: CGFloat = 0.0
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
                    Text("6 GHz").tag("6 GHz")
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
            .frame(minHeight: 300, maxHeight: .infinity) // 高さを柔軟にしつつ最小限300pxを保証し、Chartsのレイアウトエラーを防止
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
        
        // RSSIが高い順（降順）にソート。電波強度が強いAPのラベル配置を優先して好位置にするため。
        points.sort { $0.rssi > $1.rssi }
        
        // 仮想スクリーン座標での衝突検出用矩形リスト
        struct Rect {
            let xMin: Double
            let xMax: Double
            let yMin: Double
            let yMax: Double
            
            func intersects(_ other: Rect) -> Bool {
                // 衝突判定（少しマージンを持たせるためにx, y方向ともに重なりをチェック）
                return !(xMin > other.xMax || xMax < other.xMin || yMin > other.yMax || yMax < other.yMin)
            }
        }
        
        var placedRects: [Rect] = []
        
        // 配置候補のリスト（上側と下側に交互かつ外側に広げていくスロット）
        struct LabelConfig {
            let position: AnnotationPosition
            let offsetY: CGFloat
        }
        
        let candidates = [
            LabelConfig(position: .top, offsetY: -2.0),
            LabelConfig(position: .bottom, offsetY: 10.0),
            LabelConfig(position: .top, offsetY: -18.0),
            LabelConfig(position: .bottom, offsetY: 26.0),
            LabelConfig(position: .top, offsetY: -34.0),
            LabelConfig(position: .bottom, offsetY: 42.0),
            LabelConfig(position: .top, offsetY: -50.0),
            LabelConfig(position: .bottom, offsetY: 58.0),
            LabelConfig(position: .top, offsetY: -66.0),
            LabelConfig(position: .bottom, offsetY: 74.0),
        ]
        
        // 各ポイントについて最適なスロットを決定
        for idx in 0..<points.count {
            let pt = points[idx]
            
            // 仮想スクリーンサイズ
            let screenWidth = 800.0
            let screenHeight = 300.0
            
            // X座標のピクセル換算
            let xPx: Double
            if selectedBand == "2.4 GHz" {
                xPx = (pt.channel / 14.0) * screenWidth
            } else if selectedBand == "5 GHz" {
                xPx = ((pt.channel - 30.0) / 140.0) * screenWidth
            } else {
                xPx = ((pt.channel - 1.0) / 233.0) * screenWidth
            }
            
            // Y座標のピクセル換算（下が -100, 上が -30）
            let yPx = ((pt.rssi - (-100.0)) / 70.0) * screenHeight
            
            // ラベルのサイズ目安（フォントサイズ9ptでの文字幅 + パディング）
            let labelWidth = max(55.0, Double(pt.ssid.count) * 5.5 + 14.0)
            let labelHeight = 16.0
            
            var selectedConfig = candidates[0]
            var foundFit = false
            
            // 候補スロットを順番に試して、既存の配置済み矩形と衝突しないものを探す
            for config in candidates {
                let rect: Rect
                let offset = Double(config.offsetY)
                
                // X軸方向の範囲（中央揃え）
                let xMin = xPx - labelWidth / 2.0
                let xMax = xPx + labelWidth / 2.0
                
                // Y軸方向の範囲（SwiftUIのoffsetYは下がプラス、上がマイナス。グラフ座標は上がプラス）
                if config.position == .top {
                    let yMin = yPx - offset
                    let yMax = yPx - offset + labelHeight
                    rect = Rect(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
                } else {
                    let yMin = yPx - offset - labelHeight
                    let yMax = yPx - offset
                    rect = Rect(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
                }
                
                // 衝突チェック
                let hasCollision = placedRects.contains { $0.intersects(rect) }
                if !hasCollision {
                    selectedConfig = config
                    placedRects.append(rect)
                    foundFit = true
                    break
                }
            }
            
            // 万が一全てのスロットで衝突した場合は、最後の候補を割り当てる
            if !foundFit {
                let config = candidates.last!
                let offset = Double(config.offsetY)
                let xMin = xPx - labelWidth / 2.0
                let xMax = xPx + labelWidth / 2.0
                let rect: Rect
                if config.position == .top {
                    rect = Rect(xMin: xMin, xMax: xMax, yMin: yPx - offset, yMax: yPx - offset + labelHeight)
                } else {
                    rect = Rect(xMin: xMin, xMax: xMax, yMin: yPx - offset - labelHeight, yMax: yPx - offset)
                }
                placedRects.append(rect)
                selectedConfig = config
            }
            
            points[idx].labelPosition = selectedConfig.position
            points[idx].labelOffsetY = selectedConfig.offsetY
        }
        
        return points
    }
    
    // グラフビューの本体
    private var chartView: some View {
        Chart {
            ForEach(filteredAccessPoints) { ap in
                let points = generateDomePoints(for: ap)
                let apColor = colorForSSID(ap.ssid)
                
                // ドームの中身を半透明で塗りつぶす (AreaMark)
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Channel", point.channel),
                        yStart: .value("Min RSSI", -100.0),
                        yEnd: .value("RSSI (dBm)", point.rssi),
                        series: .value("AP", ap.id) // seriesによるグループ化で個別色付けを可能に
                    )
                    .foregroundStyle(apColor.opacity(0.2))
                }
                
                // なめらかな円ドーム境界線を描画 (LineMark)
                ForEach(points) { point in
                    LineMark(
                        x: .value("Channel", point.channel),
                        y: .value("RSSI (dBm)", point.rssi),
                        series: .value("AP", ap.id) // seriesによるグループ化で個別色付けを可能に
                    )
                    .foregroundStyle(apColor)
                }
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            
            // SSID名のアノテーションラベルを追加（頂点にのみ配置、重なり回避を適用）
            ForEach(peakPoints) { peak in
                PointMark(
                    x: .value("Channel", peak.channel),
                    y: .value("RSSI (dBm)", peak.rssi)
                )
                .symbolSize(0) // ドット自体は非表示にしてすっきりさせる
                .annotation(position: peak.labelPosition, alignment: .center, spacing: 4) {
                    Text(peak.ssid)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(colorForSSID(peak.ssid))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
                        .cornerRadius(4)
                        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                        .offset(y: peak.labelOffsetY) // 上下重なりを回避するための動的オフセット
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
        } else if selectedBand == "5 GHz" {
            // 5GHz: スキャンのたびにスケールが変わってガタガタ動かないよう、固定範囲 (30...170) にします
            return 30...170
        } else {
            // 6GHz: チャンネル範囲 1〜233
            return 1...233
        }
    }
    
    // X軸の目盛り（Tick）を決定
    private var xAxisTicks: [Double] {
        if selectedBand == "2.4 GHz" {
            return Array(1...13).map { Double($0) }
        } else if selectedBand == "5 GHz" {
            // 5GHz: スキャンのたびに目盛りの増減で軸幅が変動しないよう、代表的な主要チャンネルに固定します
            return [36, 48, 52, 64, 100, 116, 132, 144, 149, 165]
        } else {
            // 6GHz: 主要なPSCチャンネルなどを代表としてプロット (16チャンネルおき)
            return [5, 37, 69, 101, 133, 165, 197, 229]
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
    
    // SSIDから一意かつ決定論的な美しいパステル調カラーを生成
    private func colorForSSID(_ ssid: String) -> Color {
        if ssid.isEmpty || ssid == "非公開ネットワーク" || ssid == "Hidden Network" {
            return Color.gray.opacity(0.6)
        }
        
        // FNV-1a ハッシュでSSIDを数値化
        var hash: UInt32 = 2166136261
        for byte in ssid.utf8 {
            hash = hash ^ UInt32(byte)
            hash = hash &* 16777619
        }
        
        // 黄金比 (Golden Ratio conjugate) を用いたハッシュの分散手法
        // 類似した文字列や連続する値であっても色相が非常に綺麗に均等分散します
        let goldenRatioConjugate = 0.618033988749895
        let rawHue = Double(hash) * goldenRatioConjugate
        let hue = rawHue.truncatingRemainder(dividingBy: 1.0)
        
        // パステルカラーの調整: 彩度0.55、明度0.90で目に優しいパステル調に統一
        let saturation = 0.55
        let brightness = 0.90
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

#Preview {
    WifiAPGraphView(accessPoints: [
        WifiAPListViewModel.AccessPoint(id: "1", ssid: "Test-2.4G-A", bssid: "00:11:22:33:44:55", rssi: -55, band: "2.4 GHz", channel: 6, width: "20 MHz", security: "WPA2"),
        WifiAPListViewModel.AccessPoint(id: "2", ssid: "Test-2.4G-B", bssid: "00:11:22:33:44:66", rssi: -65, band: "2.4 GHz", channel: 8, width: "40 MHz", security: "WPA3"),
        WifiAPListViewModel.AccessPoint(id: "3", ssid: "Test-5G-A", bssid: "00:11:22:33:44:77", rssi: -45, band: "5 GHz", channel: 36, width: "80 MHz", security: "WPA2"),
        WifiAPListViewModel.AccessPoint(id: "4", ssid: "Test-6G-A", bssid: "00:11:22:33:44:88", rssi: -50, band: "6 GHz", channel: 37, width: "160 MHz", security: "WPA3")
    ])
}
