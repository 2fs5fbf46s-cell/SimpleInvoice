//
//  Blockout.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import SwiftData

@Model
final class LegacyBlockout {
    var id: UUID
    var businessID: UUID

    var title: String
    var startDate: Date
    var endDate: Date

    init(
        id: UUID = UUID(),
        businessID: UUID,
        title: String = "Blocked",
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.businessID = businessID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
