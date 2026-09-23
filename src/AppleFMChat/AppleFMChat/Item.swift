//
//  Item.swift
//  AppleFMChat
//
//  Created by ねこさん on 2026/09/23.
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
