//
//  WifiAPListViewModel.swift
//  WiFiSnifferTool
//
//  Created by Masataka Nabeshima on 2026/05/24.
//

import SwiftUI
import AppKit
import CoreWLAN
import Combine
import CoreLocation
import UniformTypeIdentifiers

@MainActor
@Observable
class WifiAPListViewModel: NSObject, CLLocationManagerDelegate {
    struct AccessPoint: Identifiable, Equatable {
        let id: String
        let ssid: String
        let bssid: String
        let rssi: Int
        let band: String
        let channel: Int
        let width: String
        let security: String
        var lostCount: Int = 0
        
        // 信号強度の段階 (0〜4)
        var signalLevel: Int {
            if rssi >= -50 { return 4 }
            if rssi >= -65 { return 3 }
            if rssi >= -80 { return 2 }
            if rssi >= -90 { return 1 }
            return 0
        }
    }
    
    var accessPoints: [AccessPoint] = []
    var isScanning: Bool = false
    var errorMessage: String? = nil
    var locationStatus: CLAuthorizationStatus = .notDetermined
    
    var searchText: String = ""
    var selectedBandFilter: String = "All"
    var selectedSortOption: String = "RSSI"
    
    private var scanTimer: Timer?
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkLocationAuthorization()
        startPeriodicScan()
    }
    
    func checkLocationAuthorization() {
        let status = locationManager.authorizationStatus
        self.locationStatus = status
        
        switch status {
        case .denied, .restricted:
            self.errorMessage = String(localized: "位置情報の権限がありません。「システム設定」＞「プライバシーとセキュリティ」＞「位置情報サービス」で本アプリの位置情報を許可してください。許可されていない場合、SSIDやBSSIDなどの情報が取得できません。")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if self.errorMessage?.contains("位置情報") == true {
                self.errorMessage = nil
            }
        @unknown default:
            break
        }
    }
    
    deinit {
        // タイマーの無効化は onDisappear で行われるため、ここでは何もしません
    }
    
    func startPeriodicScan() {
        scan()
        // 8秒ごとに自動スキャン
        scanTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
    }
    
    func stopPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    // 位置情報の設定画面を開く
    func openLocationSettings() {
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.Location-Settings.extension",
            "x-apple.systempreferences:"
        ]
        
        for urlStr in urlStrings {
            if let url = URL(string: urlStr) {
                if NSWorkspace.shared.open(url) {
                    break
                }
            }
        }
    }
    
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        
        checkLocationAuthorization()
        if locationStatus != .denied && locationStatus != .restricted {
            errorMessage = nil
        }
        
        // 1. CWWiFiClient の取得およびインターフェース取得は MainActor (メインスレッド) で行う
        guard let interface = CWWiFiClient.shared().interface() else {
            self.isScanning = false
            self.errorMessage = String(localized: "Wi-Fiインターフェースが見つかりません。")
            return
        }
        
        // 2. スキャン処理のみをバックグラウンドスレッドで実行して UI ブロックを防ぐ
        Task {
            do {
                let networks = try await Task.detached(priority: .userInitiated) {
                    // スキャンAPIはここで実行
                    if let nw = try? interface.scanForNetworks(withSSID: nil, includeHidden: false) {
                        return nw
                    } else if let nw = try? interface.scanForNetworks(withName: nil, includeHidden: false) {
                        return nw
                    } else {
                        return try interface.scanForNetworks(withSSID: nil)
                    }
                }.value
                
                // 3. メインスレッド（@MainActor）上で、スキャン結果のデータをマッピング
                var generatedIds = Set<String>()
                let aps = networks.map { network -> AccessPoint in
                    let ssid: String
                    if let rawSsid = network.ssid {
                        ssid = rawSsid
                    } else if let ssidData = network.ssidData, let decodedSsid = String(data: ssidData, encoding: .utf8) {
                        ssid = decodedSsid
                    } else if let ssidData = network.ssidData, let decodedSsid = String(data: ssidData, encoding: .ascii) {
                        ssid = decodedSsid
                    } else {
                        ssid = String(localized: "非公開ネットワーク")
                    }
                    let bssid = network.bssid ?? "00:00:00:00:00:00"
                    let rssi = network.rssiValue
                    
                    let band: String
                    if let chan = network.wlanChannel {
                        switch chan.channelBand {
                        case .band2GHz: band = "2.4 GHz"
                        case .band5GHz: band = "5 GHz"
                        case .band6GHz: band = "6 GHz"
                        @unknown default: band = "Unknown"
                        }
                    } else {
                        band = "Unknown"
                    }
                    
                    let channel = network.wlanChannel?.channelNumber ?? 0
                    
                    let width: String
                    if let chan = network.wlanChannel {
                        switch chan.channelWidth {
                        case .width20MHz: width = "20 MHz"
                        case .width40MHz: width = "40 MHz"
                        case .width80MHz: width = "80 MHz"
                        case .width160MHz: width = "160 MHz"
                        case .widthUnknown: width = "Unknown"
                        @unknown default: width = "Unknown"
                        }
                    } else {
                        width = "Unknown"
                    }
                    
                    // 暗号設定の解析（安全なコンパイル可能定数のみ使用）
                    var secList: [String] = []
                    if network.supportsSecurity(.none) { secList.append("Open") }
                    if network.supportsSecurity(.dynamicWEP) { secList.append("WEP") }
                    if network.supportsSecurity(.wpaPersonal) || network.supportsSecurity(.wpaPersonalMixed) { secList.append("WPA") }
                    if network.supportsSecurity(.wpa2Personal) { secList.append("WPA2") }
                    if network.supportsSecurity(.wpa3Personal) { secList.append("WPA3") }
                    if network.supportsSecurity(.wpaEnterprise) || network.supportsSecurity(.wpaEnterpriseMixed) { secList.append("WPA-ENT") }
                    if network.supportsSecurity(.wpa2Enterprise) { secList.append("WPA2-ENT") }
                    if network.supportsSecurity(.wpa3Enterprise) { secList.append("WPA3-ENT") }
                    
                    let security = secList.isEmpty ? "Unknown" : secList.joined(separator: "/")
                    
                    // 一意な ID の生成（同一 BSSID, SSID, Channel でも、複数検出された場合などに一意になるよう連番を付与）
                    let baseId = "\(bssid)-\(ssid)-\(channel)"
                    var uniqueId = baseId
                    var counter = 1
                    while generatedIds.contains(uniqueId) {
                        uniqueId = "\(baseId)-\(counter)"
                        counter += 1
                    }
                    generatedIds.insert(uniqueId)
                    
                    return AccessPoint(
                        id: uniqueId,
                        ssid: ssid,
                        bssid: bssid,
                        rssi: rssi,
                        band: band,
                        channel: channel,
                        width: width,
                        security: security
                    )
                }
                
                // 既存のアクセスポイントを bssid-ssid-channel の複合キーで引けるように辞書化
                var existingAPs = [String: AccessPoint]()
                for ap in self.accessPoints {
                    let key = "\(ap.bssid)-\(ap.ssid)-\(ap.channel)"
                    existingAPs[key] = ap
                }
                
                var newAccessPoints: [AccessPoint] = []
                var foundKeys = Set<String>()
                
                // 今回のスキャンで検出されたAPを処理
                for var newAP in aps {
                    let key = "\(newAP.bssid)-\(newAP.ssid)-\(newAP.channel)"
                    
                    // スキャン結果自体の重複（同一周波数・同一SSID）を防止
                    if foundKeys.contains(key) {
                        continue
                    }
                    
                    if let existing = existingAPs[key] {
                        // 既に存在する場合は、元の id を引き継ぎつつ最新の情報に更新（lostCount は 0 にリセット）
                        let updatedAP = AccessPoint(
                            id: existing.id,
                            ssid: newAP.ssid,
                            bssid: newAP.bssid,
                            rssi: newAP.rssi,
                            band: newAP.band,
                            channel: newAP.channel,
                            width: newAP.width,
                            security: newAP.security,
                            lostCount: 0
                        )
                        newAccessPoints.append(updatedAP)
                    } else {
                        // 新しく検出されたAP
                        newAP.lostCount = 0
                        newAccessPoints.append(newAP)
                    }
                    foundKeys.insert(key)
                }
                
                // 今回検出されなかった既存のAPの連続失敗カウントを増やす（エイジング処理）
                for ap in self.accessPoints {
                    let key = "\(ap.bssid)-\(ap.ssid)-\(ap.channel)"
                    if !foundKeys.contains(key) {
                        var updatedAP = ap
                        updatedAP.lostCount += 1
                        // 3回連続で見つからなければ消去（2回目までは保持）
                        if updatedAP.lostCount < 3 {
                            newAccessPoints.append(updatedAP)
                        }
                    }
                }
                
                self.accessPoints = newAccessPoints
                self.isScanning = false
            } catch {
                self.isScanning = false
                self.errorMessage = String(localized: "スキャン失敗: ") + error.localizedDescription
            }
        }
    }
    
    var filteredAccessPoints: [AccessPoint] {
        var result = accessPoints
        
        // 検索文字によるフィルタリング
        if !searchText.isEmpty {
            result = result.filter { ap in
                ap.ssid.localizedCaseInsensitiveContains(searchText) ||
                ap.bssid.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 周波数帯（バンド）フィルター
        if selectedBandFilter != "All" {
            result = result.filter { $0.band == selectedBandFilter }
        }
        
        // ソート処理
        switch selectedSortOption {
        case "RSSI":
            result.sort { $0.rssi > $1.rssi }
        case "SSID":
            result.sort { $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending }
        case "Channel":
            result.sort { $0.channel < $1.channel }
        default:
            break
        }
        
        return result
    }
    
    /// 表示中のアクセスポイント一覧をCSVとしてエクスポートします。
    func exportToCSV() {
        let aps = filteredAccessPoints
        guard !aps.isEmpty else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "wifi_access_points_\(dateString()).csv"
        savePanel.canCreateDirectories = true
        savePanel.title = String(localized: "CSVファイルを保存")
        
        let response = savePanel.runModal()
        if response == .OK {
            guard let url = savePanel.url else { return }
            
            // CSVの生成
            var csvText = "SSID,BSSID,RSSI (dBm),Band,Channel,Channel Width,Security\n"
            for ap in aps {
                let escapedSSID = escapeCSVField(ap.ssid)
                let escapedBSSID = escapeCSVField(ap.bssid)
                let escapedBand = escapeCSVField(ap.band)
                let escapedWidth = escapeCSVField(ap.width)
                let escapedSecurity = escapeCSVField(ap.security)
                csvText += "\(escapedSSID),\(escapedBSSID),\(ap.rssi),\(escapedBand),\(ap.channel),\(escapedWidth),\(escapedSecurity)\n"
            }
            
            do {
                try csvText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.errorMessage = String(localized: "CSV保存失敗: ") + error.localizedDescription
            }
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
    
    // 位置情報権限の更新通知を受けたとき
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.checkLocationAuthorization()
            self.scan()
        }
    }
}
