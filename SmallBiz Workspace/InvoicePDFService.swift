import Foundation
import SwiftData

enum BusinessSnapshotLockReason: String {
    case sent
    case portal
    case paid
    case finalized
    case historical
}

enum InvoicePDFService {

    static func resolvedBusinessProfile(for invoice: Invoice, profiles: [BusinessProfile]) -> BusinessProfile? {
        if let match = profiles.first(where: { $0.businessID == invoice.businessID }) {
            return match
        }
        return profiles.first
    }

    static func resolvedBusiness(for invoice: Invoice, businesses: [Business]) -> Business? {
        if let match = businesses.first(where: { $0.id == invoice.businessID }) {
            return match
        }
        return businesses.first
    }

    static func effectiveInvoiceTemplateKey(invoice: Invoice, business: Business?) -> InvoiceTemplateKey {
        if let override = InvoiceTemplateKey.from(invoice.invoiceTemplateKeyOverride) {
            return override
        }
        if let business,
           let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) {
            return key
        }
        return .modern_clean
    }

    @MainActor
    static func lockBusinessSnapshotIfNeeded(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?,
        reason: BusinessSnapshotLockReason = .historical,
        replaceExistingUnlockedSnapshot: Bool = false
    ) -> BusinessSnapshot {
        // Before the lock stamp, while this invoice still counts as a draft, so a
        // document being finalized records the client it is actually addressed to.
        invoice.captureClientSnapshotIfNeeded()

        if let snapshot = invoice.businessSnapshot,
           invoice.hasBusinessSnapshotLockRecord || !replaceExistingUnlockedSnapshot {
            stampBusinessSnapshotLock(invoice: invoice, reason: reason)
            try? context?.save()
            return snapshot
        }

        let profile = resolvedBusinessProfile(for: invoice, profiles: profiles)
        let snapshot = BusinessSnapshot(profile: profile)

        invoice.businessSnapshot = snapshot
        stampBusinessSnapshotLock(invoice: invoice, reason: reason)
        try? context?.save()

        return snapshot
    }

    @MainActor
    static func businessSnapshotForRendering(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?
    ) -> BusinessSnapshot {
        invoice.captureClientSnapshotIfNeeded()

        if invoice.isBusinessInfoLocked {
            return lockBusinessSnapshotIfNeeded(
                invoice: invoice,
                profiles: profiles,
                context: context,
                reason: inferredLockReason(for: invoice),
                replaceExistingUnlockedSnapshot: false
            )
        }

        let profile = resolvedBusinessProfile(for: invoice, profiles: profiles)
        return BusinessSnapshot(profile: profile)
    }

    @MainActor
    static func refreshBusinessInfoForDraft(invoice: Invoice, context: ModelContext?) -> Bool {
        guard invoice.canRefreshBusinessInfo else { return false }

        let hadStoredBusinessInfo = invoice.businessSnapshotData != nil ||
            invoice.businessSnapshotLockedAt != nil ||
            invoice.businessSnapshotLockReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        invoice.businessSnapshot = nil
        invoice.businessSnapshotLockedAt = nil
        invoice.businessSnapshotLockReason = nil
        try? context?.save()

        return hadStoredBusinessInfo
    }

    @MainActor
    private static func stampBusinessSnapshotLock(invoice: Invoice, reason: BusinessSnapshotLockReason) {
        if invoice.businessSnapshotLockedAt == nil {
            invoice.businessSnapshotLockedAt = Date()
        }
        if invoice.businessSnapshotLockReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            invoice.businessSnapshotLockReason = reason.rawValue
        }
    }

    @MainActor
    private static func inferredLockReason(for invoice: Invoice) -> BusinessSnapshotLockReason {
        if let reason = BusinessSnapshotLockReason(rawValue: invoice.normalizedBusinessSnapshotLockReason) {
            return reason
        }
        if invoice.isPaid {
            return .paid
        }
        if invoice.hasPortalUploadRecord {
            return .portal
        }
        if invoice.estimateLocksBusinessSnapshot {
            return .sent
        }
        return .historical
    }

    @MainActor
    static func makePDFData(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?,
        businesses: [Business] = [],
        lockBusinessSnapshot: Bool = false,
        lockReason: BusinessSnapshotLockReason = .finalized
    ) -> Data {
        let snapshot = lockBusinessSnapshot
            ? lockBusinessSnapshotIfNeeded(
                invoice: invoice,
                profiles: profiles,
                context: context,
                reason: lockReason,
                replaceExistingUnlockedSnapshot: true
            )
            : businessSnapshotForRendering(
                invoice: invoice,
                profiles: profiles,
                context: context
            )
        let business = resolvedBusiness(for: invoice, businesses: businesses)
        let templateKey = effectiveInvoiceTemplateKey(invoice: invoice, business: business)
        return InvoicePDFGenerator.makePDFData(
            invoice: InvoiceRenderModel(invoice: invoice),
            business: snapshot,
            templateKey: templateKey
        )
    }

    /// Render without blocking the interface.
    ///
    /// Reading the models and locking the business snapshot still happen on the
    /// main actor — they have to — but the layout and rasterizing, which is where
    /// a long invoice spends its time, run off it. Prefer this anywhere the user
    /// is waiting: share, export, portal upload, mail attachment.
    static func makePDFDataOffMainThread(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?,
        businesses: [Business] = [],
        lockBusinessSnapshot: Bool = false,
        lockReason: BusinessSnapshotLockReason = .finalized
    ) async -> Data {
        let (renderModel, snapshot, templateKey) = await MainActor.run {
            () -> (InvoiceRenderModel, BusinessSnapshot, InvoiceTemplateKey) in
            let snapshot = lockBusinessSnapshot
                ? lockBusinessSnapshotIfNeeded(
                    invoice: invoice,
                    profiles: profiles,
                    context: context,
                    reason: lockReason,
                    replaceExistingUnlockedSnapshot: true
                )
                : businessSnapshotForRendering(
                    invoice: invoice,
                    profiles: profiles,
                    context: context
                )
            let business = resolvedBusiness(for: invoice, businesses: businesses)
            return (
                InvoiceRenderModel(invoice: invoice),
                snapshot,
                effectiveInvoiceTemplateKey(invoice: invoice, business: business)
            )
        }

        return await Task.detached(priority: .userInitiated) {
            InvoicePDFGenerator.makePDFData(
                invoice: renderModel,
                business: snapshot,
                templateKey: templateKey
            )
        }.value
    }
}
