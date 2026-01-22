//
//  BusinessMigration.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftData

enum BusinessMigration {

    /// Increment this if you ever add another migration
    static let currentVersion = 1

    static func runIfNeeded(
        modelContext: ModelContext,
        activeBiz: ActiveBusinessStore
    ) throws {

        let defaults = UserDefaults.standard
        let key = "businessMigrationVersion"

        let lastRunVersion = defaults.integer(forKey: key)
        guard lastRunVersion < currentVersion else {
            return // already migrated
        }

        // 1️⃣ Ensure at least one Business exists
        let businesses = try modelContext.fetch(FetchDescriptor<Business>())
        let defaultBusiness: Business

        if let existing = businesses.first {
            defaultBusiness = existing
        } else {
            let created = Business(name: "Default Business", isActive: true)
            modelContext.insert(created)
            try modelContext.save()
            defaultBusiness = created
        }

        // 2️⃣ Ensure active business is set
        activeBiz.setActiveBusiness(defaultBusiness.id)

        // Build a set of valid business IDs
        let validBusinessIDs = Set(
            try modelContext
                .fetch(FetchDescriptor<Business>())
                .map { $0.id }
        )

        // 3️⃣ Backfill Clients
        let clients = try modelContext.fetch(FetchDescriptor<Client>())
        for c in clients {
            if !validBusinessIDs.contains(c.businessID) {
                c.businessID = defaultBusiness.id
            }
        }

        // 4️⃣ Backfill Invoices
        let invoices = try modelContext.fetch(FetchDescriptor<Invoice>())
        for i in invoices {
            if !validBusinessIDs.contains(i.businessID) {
                i.businessID = defaultBusiness.id
            }
        }

        // 5️⃣ Backfill Contracts
        let contracts = try modelContext.fetch(FetchDescriptor<Contract>())
        for c in contracts {
            if !validBusinessIDs.contains(c.businessID) {
                c.businessID = defaultBusiness.id
            }
        }

        try modelContext.save()

        // 6️⃣ Mark migration complete
        defaults.set(currentVersion, forKey: key)

        print("✅ Business migration v\(currentVersion) completed")
    }
}
