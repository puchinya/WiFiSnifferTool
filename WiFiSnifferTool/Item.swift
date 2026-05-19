//
//  Item.swift
//  WiFiSnifferTool
//
//  Created by 鍋島雅貴 on 2026/05/20.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
