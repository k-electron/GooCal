//
//  Item.swift
//  GooCal
//
//  Created by Karim Fatehi on 9/18/26.
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
