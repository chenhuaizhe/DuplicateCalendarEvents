//
//  Item.swift
//  DuplicateCalendarEvents
//
//  Created by cy on 2024/10/10.
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