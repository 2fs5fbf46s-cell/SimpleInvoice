//
//  Item.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/11/26.
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
