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
    static let currentVersion = 11

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

        // 6️⃣ Backfill invoice template keys (CloudKit-safe String values)
        for business in try modelContext.fetch(FetchDescriptor<Business>()) {
            let key = business.defaultInvoiceTemplateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if InvoiceTemplateKey.from(key) == nil {
                business.defaultInvoiceTemplateKey = InvoiceTemplateKey.modern_clean.rawValue
            }
        }

        let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
        for invoice in allInvoices {
            if let overrideRaw = invoice.invoiceTemplateKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !overrideRaw.isEmpty,
               InvoiceTemplateKey.from(overrideRaw) == nil {
                invoice.invoiceTemplateKeyOverride = nil
            }

            // Existing invoices should not enqueue uploads until user edits/saves again.
            invoice.portalNeedsUpload = false
            invoice.portalUploadInFlight = false
            invoice.portalLastUploadError = nil
            if let blobUrl = invoice.portalLastUploadedBlobUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
               blobUrl.isEmpty {
                invoice.portalLastUploadedBlobUrl = nil
            }

            if let lastMs = invoice.portalLastUploadedAtMs, lastMs < 0 {
                invoice.portalLastUploadedAtMs = nil
            }
            if let hash = invoice.portalLastUploadedHash?.trimmingCharacters(in: .whitespacesAndNewlines),
               hash.isEmpty {
                invoice.portalLastUploadedHash = nil
            }

            if let bookingID = invoice.sourceBookingRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
               bookingID.isEmpty {
                invoice.sourceBookingRequestId = nil
            }
        }

        let allClients = try modelContext.fetch(FetchDescriptor<Client>())
        for client in allClients {
            if let preferredRaw = client.preferredInvoiceTemplateKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preferredRaw.isEmpty,
               InvoiceTemplateKey.from(preferredRaw) == nil {
                client.preferredInvoiceTemplateKey = nil
            }
        }

        let allContracts = try modelContext.fetch(FetchDescriptor<Contract>())
        for contract in allContracts {
            // Existing contracts should not enqueue uploads until user edits/saves again.
            contract.portalNeedsUpload = false
            contract.portalUploadInFlight = false
            contract.portalLastUploadError = nil

            if let lastMs = contract.portalLastUploadedAtMs, lastMs < 0 {
                contract.portalLastUploadedAtMs = nil
            }
            if let hash = contract.portalLastUploadedHash?.trimmingCharacters(in: .whitespacesAndNewlines),
               hash.isEmpty {
                contract.portalLastUploadedHash = nil
            }
        }

        // 7️⃣ Job stage normalization:
        let allJobs = try modelContext.fetch(FetchDescriptor<Job>())
        let now = Date()
        for job in allJobs {
            if JobStage(rawValue: job.stageRaw) == nil {
                job.stageRaw = JobStage.booked.rawValue
            }
            if job.sourceBookingRequestId != nil,
               job.stage == .completed,
               job.startDate >= now {
                job.stage = .booked
            }
        }

        try modelContext.save()

        // 8️⃣ Mark migration complete
        defaults.set(currentVersion, forKey: key)

        print("✅ Business migration v\(currentVersion) completed")
    }
}
