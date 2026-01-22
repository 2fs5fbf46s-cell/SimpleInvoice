//
//  ActiveBusinessProvider.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import SwiftData

enum ActiveBusinessProvider {
    static func getOrCreateActiveBusiness(in context: ModelContext) throws -> Business {
        // Prefer the active one
        let descriptor = FetchDescriptor<Business>()
        let all = try context.fetch(descriptor)

        if let active = all.first(where: { $0.isActive }) {
            return active
        }
        if let first = all.first {
            first.isActive = true
            try context.save()
            return first
        }

        // Create one if none exist
        let new = Business(
            id: Foundation.UUID(),
            name: "My Business",
            isActive: true,
            defaultTaxRate: 0,
            currencyCode: "USD",
            travelBufferMinutes: 15,
            workdayStartMinutes: 9 * 60,
            workdayEndMinutes: 17 * 60
        )
        context.insert(new)
        try context.save()
        return new
    }
}
