//
//  InvoiceActivityPullService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Brings portal payments and views into the app.
///
/// A client paying online used to reach the app only if the owner opened
/// that invoice's portal page and closed it again — nothing else asked. This
/// pulls the backend's invoice activity feed (on the "invoice paid" push, at
/// launch and on foreground, like EstimateAcceptancePullService) and records
/// an online payment as a payment, so the balance and "Paid" follow.
@MainActor
enum InvoiceActivityPullService {
    private static func watermarkKey(businessID: UUID) -> String {
        "sbw.invoiceActivity.pullWatermarkMs.\(businessID.uuidString)"
    }

    static func pull(context: ModelContext, businessID: UUID?) async {
        guard let businessID else { return }

        let defaults = UserDefaults.standard
        let key = watermarkKey(businessID: businessID)
        var watermarkMs = defaults.double(forKey: key)

        // The feed pages at 200; keep going while it says there's more.
        for _ in 0..<20 {
            let page: PortalBackend.InvoiceActivityPage
            do {
                page = try await PortalBackend.shared.pullInvoiceActivity(
                    since: Date(timeIntervalSince1970: max(watermarkMs, 0) / 1000)
                )
            } catch {
                SBWLog.ui.problem("[InvoiceActivity] pull failed: \(error)")
                return
            }
            guard !page.items.isEmpty else { return }

            for item in page.items.sorted(by: { $0.updatedAtMs < $1.updatedAtMs }) {
                apply(item, businessID: businessID, context: context)
                watermarkMs = max(watermarkMs, item.updatedAtMs)
            }
            try? context.save()
            defaults.set(watermarkMs, forKey: key)

            guard page.hasMore == true else { return }
        }
    }

    /// Idempotent: a repeat of the same item changes nothing.
    static func apply(_ item: PortalBackend.InvoiceActivityDTO, businessID: UUID, context: ModelContext) {
        guard let id = UUID(uuidString: item.invoiceId),
              let invoice = try? context.fetch(
                  FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == id })
              ).first,
              invoice.businessID == businessID,
              invoice.documentType != "estimate"
        else { return }

        if let ms = item.viewedAtMs, ms > 0, invoice.viewedAt == nil {
            invoice.viewedAt = Date(timeIntervalSince1970: ms / 1000)
        }
        if let ms = item.sentAtMs, ms > 0, invoice.sentAt == nil {
            invoice.sentAt = Date(timeIntervalSince1970: ms / 1000)
        }
        if let ms = item.lastReminderAtMs, ms > 0 {
            let date = Date(timeIntervalSince1970: ms / 1000)
            if (invoice.lastReminderAt ?? .distantPast) < date { invoice.lastReminderAt = date }
        }

        guard item.paid == true, !invoice.isPaid else { return }
        let alreadyRecorded = (invoice.payments ?? []).contains { $0.source == "portal" }
        guard !alreadyRecorded else { return }

        let paidAt = item.paidAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        let amount = item.paidOnlineCents.flatMap { $0 > 0 ? $0 : nil } ?? invoice.balanceDueCents
        if amount > 0 {
            _ = try? InvoicePaymentService.record(
                on: invoice,
                amountCents: amount,
                paidAt: paidAt,
                method: item.provider ?? "card",
                note: "Paid in the client portal",
                source: "portal",
                context: context
            )
        }
        // The portal says it's settled; trust it even if the amounts disagree
        // (a total edited after the client paid, say).
        if !invoice.isPaid {
            invoice.isPaid = true
        }
    }
}
