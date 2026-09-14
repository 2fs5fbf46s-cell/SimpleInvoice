import Foundation
import SwiftData

/// Turns the backend's server-generated recurring-invoice records into real
/// local `Invoice`s: fetches what changed since this device's own watermark,
/// mints a genuine sequential invoice number (that counter only lives
/// on-device), and inserts — nothing here is sent to the client. The owner
/// still has to open and send it, same as any manually-created draft.
@MainActor
enum RecurringInvoicePullService {
    private static func watermarkKey(businessID: UUID) -> String {
        "sbw.recurring.pullWatermarkMs.\(businessID.uuidString)"
    }

    static func pullAndMaterialize(context: ModelContext, businessID: UUID?) async {
        guard let businessID else { return }

        let defaults = UserDefaults.standard
        let key = watermarkKey(businessID: businessID)
        let watermarkMs = defaults.double(forKey: key)
        let since = watermarkMs > 0
            ? Date(timeIntervalSince1970: watermarkMs / 1000)
            : Date(timeIntervalSince1970: 0)

        let generated: [GeneratedRecurringInvoiceDTO]
        do {
            generated = try await PortalBackend.shared.pullGeneratedRecurringInvoices(since: since)
        } catch {
            SBWLog.ui.problem("[Recurring] pull failed: \(error)")
            return
        }

        guard !generated.isEmpty else { return }

        var latestUpdatedAtMs = watermarkMs
        var materializedCount = 0
        for item in generated {
            if materialize(item, businessID: businessID, context: context) {
                materializedCount += 1
            }
            latestUpdatedAtMs = max(latestUpdatedAtMs, item.updatedAtMs)
        }

        if materializedCount > 0 {
            do {
                try context.save()
            } catch {
                SBWLog.ui.problem("[Recurring] failed to save materialized invoices: \(error)")
            }
        }

        // Advance the watermark even for entries this device chose to skip
        // (e.g. an unknown client) — the KV record itself is the durable
        // record of "this existed," reprocessing it every pull would never
        // succeed differently, and it stops showing up once the owner deals
        // with it through the normal invoice flow regardless.
        defaults.set(latestUpdatedAtMs, forKey: key)
    }

    /// Exposed at `internal` (not `private`) rather than `@testable`-only
    /// visibility games, so tests can drive materialization directly with a
    /// hand-built DTO instead of needing to mock the network call in
    /// `pullAndMaterialize`.
    @discardableResult
    static func materialize(
        _ item: GeneratedRecurringInvoiceDTO,
        businessID: UUID,
        context: ModelContext
    ) -> Bool {
        guard let invoiceUUID = UUID(uuidString: item.invoiceId) else { return false }

        // Idempotent by design: a repeat pull (or a sibling device's own
        // pull, synced in via CloudKit) must never create a duplicate.
        let alreadyExists = (try? context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == invoiceUUID })
        ))?.isEmpty == false
        guard !alreadyExists else { return false }

        guard let clientUUID = UUID(uuidString: item.clientId) else { return false }
        let client = (try? context.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientUUID })
        ))?.first
        guard let client else { return false }

        let profile = resolveProfile(businessID: businessID, context: context)
        let realInvoiceNumber = InvoiceNumberGenerator.consumeNextNumber(profile: profile)

        let lineItems = item.lineItems.map {
            LineItem(itemDescription: $0.description, quantity: $0.quantity, unitPrice: $0.unitPrice)
        }

        let dueDate = Date(timeIntervalSince1970: item.dueAtMs / 1000)
        let netDays = max(0, Calendar.current.dateComponents([.day], from: .now, to: dueDate).day ?? 14)

        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: realInvoiceNumber,
            issueDate: .now,
            dueDate: dueDate,
            paymentTerms: "Net \(netDays)",
            notes: "",
            thankYou: profile.defaultThankYou,
            termsAndConditions: profile.defaultTerms,
            taxRate: item.taxRate,
            discountAmount: Double(item.discountAmountCents) / 100.0,
            isPaid: false,
            documentType: "invoice",
            isRecurringGenerated: true,
            recurringReviewedAt: nil,
            portalNeedsUpload: true,
            client: client,
            job: nil,
            items: lineItems
        )
        invoice.id = invoiceUUID

        context.insert(invoice)
        return true
    }

    private static func resolveProfile(businessID: UUID, context: ModelContext) -> BusinessProfile {
        let existing = (try? context.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })
        ))?.first
        if let existing { return existing }

        let created = BusinessProfile(businessID: businessID)
        context.insert(created)
        return created
    }
}
