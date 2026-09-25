import Foundation
import SwiftData

// MARK: - Business Profile

@Model
final class BusinessProfile {
    var businessID: UUID = UUID()

    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""


    // Client Portal
    var portalEnabled: Bool = true
    var defaultThankYou: String = "Thank you for your business!"
    var defaultTerms: String = "Payment is due by the due date listed on this invoice."
    var defaultEstimatePaymentTerms: String = "Valid for 14 days"
    var defaultEstimateNotes: String = ""
    var defaultEstimateThankYou: String = "Thank you for considering this estimate."
    var defaultEstimateTerms: String = "Pricing and scope are valid for the period shown on this estimate."

    // Booking Portal
    var bookingSlug: String = ""
    var bookingURL: String = ""
    var bookingEnabled: Bool = true
    var bookingHoursText: String = ""
    var bookingInstructions: String = ""
    var bookingServicesText: String? = nil
    var bookingServicesJSON: String = ""
    var bookingHoursJSON: String = ""
    var bookingSlotMinutes: Int = 30
    var bookingTimeIncrementMinutes: Int = 30
    var bookingMinBookingMinutes: Int? = nil
    var bookingMaxBookingMinutes: Int? = nil
    var bookingAllowSameDay: Bool? = nil
    var bookingBrandName: String? = nil
    var bookingOwnerEmail: String? = nil

    var logoData: Data? = nil

    // Overdue payment reminders (client-facing email, opt-in). Cadence is
    // "days overdue before the first — and only — nudge fires."
    var overdueReminderEnabled: Bool = false
    var overdueReminderCadenceDays: Int = 7

    var invoicePrefix: String = "SI"
    var nextInvoiceNumber: Int = 1
    var lastInvoiceYear: Int = Calendar.current.component(.year, from: Foundation.Date())

    var catalogCategoriesText: String = """
General
Photography
DJ
Audio/Visual
Installations
Backline
Other
"""

    init(
        businessID: UUID = UUID(),
        name: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        defaultThankYou: String = "Thank you for your business!",
        defaultTerms: String = "Payment is due by the due date listed on this invoice.",
        defaultEstimatePaymentTerms: String = "Valid for 14 days",
        defaultEstimateNotes: String = "",
        defaultEstimateThankYou: String = "Thank you for considering this estimate.",
        defaultEstimateTerms: String = "Pricing and scope are valid for the period shown on this estimate.",
        bookingSlug: String = "",
        bookingURL: String = "",
        bookingEnabled: Bool = true,
        bookingHoursText: String = "",
        bookingInstructions: String = "",
        bookingServicesText: String? = nil,
        bookingServicesJSON: String = "",
        bookingHoursJSON: String = "",
        bookingSlotMinutes: Int = 30,
        bookingTimeIncrementMinutes: Int = 30,
        bookingMinBookingMinutes: Int? = nil,
        bookingMaxBookingMinutes: Int? = nil,
        bookingAllowSameDay: Bool? = nil,
        bookingBrandName: String? = nil,
        bookingOwnerEmail: String? = nil,
        logoData: Data? = nil,
        overdueReminderEnabled: Bool = false,
        overdueReminderCadenceDays: Int = 7,
        invoicePrefix: String = "SI",
        nextInvoiceNumber: Int = 1,
        lastInvoiceYear: Int = Calendar.current.component(.year, from: Foundation.Date()),
        catalogCategoriesText: String = """
General
Photography
DJ
Audio/Visual
Backline
Other
"""
    ) {
        self.businessID = businessID
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.defaultThankYou = defaultThankYou
        self.defaultTerms = defaultTerms
        self.defaultEstimatePaymentTerms = defaultEstimatePaymentTerms
        self.defaultEstimateNotes = defaultEstimateNotes
        self.defaultEstimateThankYou = defaultEstimateThankYou
        self.defaultEstimateTerms = defaultEstimateTerms
        self.bookingSlug = bookingSlug
        self.bookingURL = bookingURL
        self.bookingEnabled = bookingEnabled
        self.bookingHoursText = bookingHoursText
        self.bookingInstructions = bookingInstructions
        self.bookingServicesText = bookingServicesText
        self.bookingServicesJSON = bookingServicesJSON
        self.bookingHoursJSON = bookingHoursJSON
        self.bookingSlotMinutes = bookingSlotMinutes
        self.bookingTimeIncrementMinutes = bookingTimeIncrementMinutes
        self.bookingMinBookingMinutes = bookingMinBookingMinutes
        self.bookingMaxBookingMinutes = bookingMaxBookingMinutes
        self.bookingAllowSameDay = bookingAllowSameDay
        self.bookingBrandName = bookingBrandName
        self.bookingOwnerEmail = bookingOwnerEmail
        self.logoData = logoData
        self.overdueReminderEnabled = overdueReminderEnabled
        self.overdueReminderCadenceDays = overdueReminderCadenceDays
        self.invoicePrefix = invoicePrefix
        self.nextInvoiceNumber = nextInvoiceNumber
        self.lastInvoiceYear = lastInvoiceYear
        self.catalogCategoriesText = catalogCategoriesText
    }
}

// MARK: - Business Snapshot

struct BusinessSnapshot: Codable {
    var name: String
    var address: String
    var phone: String
    var email: String
    var logoData: Data?

    init(
        name: String = "",
        address: String = "",
        phone: String = "",
        email: String = "",
        logoData: Data? = nil
    ) {
        self.name = name
        self.address = address
        self.phone = phone
        self.email = email
        self.logoData = logoData
    }

    init(profile: BusinessProfile?) {
        self.name = profile?.name ?? ""
        self.address = profile?.address ?? ""
        self.phone = profile?.phone ?? ""
        self.email = profile?.email ?? ""
        self.logoData = profile?.logoData
    }
}

// MARK: - Client

@Model
final class Client {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()
    var portalEnabled: Bool = true
    var preferredInvoiceTemplateKey: String? = nil
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    /// The owner's own notes (gate codes, preferences). Never sent to the client.
    var notes: String = ""
    /// Set when archived: out of the Clients list and pickers, records kept.
    var archivedAt: Date? = nil
    /// Nil for clients made before this was tracked.
    var createdAt: Date? = nil

    // ✅ ARRAY-side inverses for CloudKit (avoid circular macro issues)
    @Relationship(inverse: \Invoice.client)
    var invoices: [Invoice]? = []
    // Cascade: a join row exists only to link this record to a file. Left to
    // nullify (the default) it survives its owner as an invisible orphan that
    // accumulates forever and syncs to CloudKit. The FileItem itself is not
    // cascaded — it lives in the folder workspace and other records may use it.
    @Relationship(deleteRule: .cascade, inverse: \ClientAttachment.client)
    var attachments: [ClientAttachment]? = nil



    @Relationship(inverse: \Contract.client)
    var contracts: [Contract]? = []

    init(
        businessID: UUID = UUID(),
        preferredInvoiceTemplateKey: String? = nil,
        name: String = "",
        email: String = "",
        phone: String = "",
        address: String = ""
    ) {
        self.businessID = businessID
        self.preferredInvoiceTemplateKey = preferredInvoiceTemplateKey
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.createdAt = .now
    }

    var isArchived: Bool { archivedAt != nil }
}

// MARK: - Invoice

@Model
final class Invoice {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()
    var clientID: UUID? = nil

    var businessSnapshotData: Data? = nil
    var businessSnapshotLockedAt: Date? = nil
    var businessSnapshotLockReason: String? = nil

    /// Who this was billed to, copied onto the invoice. See `ClientSnapshot`:
    /// `client` is a plain relationship with no delete rule, so this is what
    /// keeps a sent invoice readable after the client record is gone.
    var clientSnapshotData: Data? = nil

    var invoiceNumber: String = ""
    var issueDate: Date = Foundation.Date()
    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Foundation.Date()) ?? Foundation.Date()

    var paymentTerms: String = "Net 14"
    var notes: String = ""

    var thankYou: String = ""
    var termsAndConditions: String = ""

    var taxRate: Double = 0.0
    var discountAmount: Double = 0.0

    var isPaid: Bool = false
    var documentType: String = "invoice"   // "invoice" | "estimate"
    var sourceBookingRequestId: String? = nil
    var sourceEstimateId: String? = nil
    var sourceBookingDepositAmountCents: Int? = nil
    var sourceBookingDepositPaidAtMs: Int? = nil
    var sourceBookingDepositInvoiceId: String? = nil

    /// Set when this invoice IS a deposit tied to a bundled Contract (as
    /// opposed to sourceBookingDepositInvoiceId above, which points AT a
    /// deposit invoice from a regular invoice). Uploaded to the backend so
    /// the Stripe checkout route can trace a paid deposit back to its
    /// contract — see PortalBackend.indexInvoiceForPortalDirectory.
    var sourceContractId: String? = nil

    /// True when this invoice was materialized from a recurring schedule's
    /// server-side generation rather than created by hand — the thing that
    /// actually distinguishes it from any other invoice nobody has reviewed
    /// yet. `recurringReviewedAt` stays nil until the owner actually opens
    /// it — that's what keeps it showing up as a Today "ready to review"
    /// card, and what stops the card from coming back once it's been seen.
    var isRecurringGenerated: Bool = false
    var recurringReviewedAt: Date? = nil

    var pdfRelativePath: String = ""
    var invoiceTemplateKeyOverride: String? = nil
    var portalNeedsUpload: Bool = true
    var portalUploadInFlight: Bool = false
    var portalLastUploadedAtMs: Int64? = nil
    var portalLastUploadError: String? = nil
    var portalLastUploadedBlobUrl: String? = nil
    var portalLastUploadedHash: String? = nil


    // ✅ Single-side relationship stays plain (inverse declared on Client.invoices)
    var client: Client? = nil

    // ✅ NEW: Optional Job link (enables workflow + Files workspace)
    var job: Job? = nil

    // ✅ ARRAY-side inverse for Contract.invoice
    @Relationship(inverse: \Contract.invoice)
    var contracts: [Contract]? = []
    // ✅ Contracts created FROM this estimate (inverse of Contract.estimate)
    @Relationship(inverse: \Contract.estimate)
    var estimateContracts: [Contract]? = []


    // ✅ Items can stay as-is; we maintain LineItem.invoice in code for stability
    @Relationship(deleteRule: .cascade)
    var items: [LineItem]? = []

    // Cascade: a join row exists only to link this record to a file. Left to
    // nullify (the default) it survives its owner as an invisible orphan that
    // accumulates forever and syncs to CloudKit. The FileItem itself is not
    // cascaded — it lives in the folder workspace and other records may use it.
    @Relationship(deleteRule: .cascade, inverse: \InvoiceAttachment.invoice)
    var attachments: [InvoiceAttachment]? = nil

    // MARK: - Invoice lifecycle
    /// When the owner sent it (Send Invoice), or when the app first saw it
    /// was already in the client's portal. See `wasSent`.
    var sentAt: Date? = nil
    /// First time the client opened it in the portal (reported by the
    /// backend's invoice activity feed).
    var viewedAt: Date? = nil
    var lastReminderAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \InvoicePayment.invoice)
    var payments: [InvoicePayment]? = nil
    
    
    // MARK: - Estimate workflow
    var estimateStatus: String = "draft"     // draft | sent | accepted | declined
    var estimateAcceptedAt: Date? = nil
    var estimateDeclinedAt: Date? = nil
    /// When a declined estimate was reopened to revise and resend. Any
    /// client decision from before this is about the old version and is
    /// ignored — see EstimateDecisionSync.setEstimateDecision.
    var estimateReopenedAt: Date? = nil


    init(
        businessID: UUID = UUID(),
        businessSnapshotData: Data? = nil,
        invoiceNumber: String,
        issueDate: Date = Foundation.Date(),
        dueDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Foundation.Date()) ?? Foundation.Date(),
        paymentTerms: String = "Net 14",
        notes: String = "",
        thankYou: String = "",
        termsAndConditions: String = "",
        taxRate: Double = 0.0,
        discountAmount: Double = 0.0,
        isPaid: Bool = false,
        documentType: String = "invoice",
        sourceBookingRequestId: String? = nil,
        sourceEstimateId: String? = nil,
        isRecurringGenerated: Bool = false,
        recurringReviewedAt: Date? = nil,
        pdfRelativePath: String = "",
        invoiceTemplateKeyOverride: String? = nil,
        portalNeedsUpload: Bool = true,
        portalUploadInFlight: Bool = false,
        portalLastUploadedAtMs: Int64? = nil,
        portalLastUploadError: String? = nil,
        portalLastUploadedBlobUrl: String? = nil,
        portalLastUploadedHash: String? = nil,
        client: Client? = nil,
        job: Job? = nil,
        items: [LineItem] = []
    ) {
        self.businessID = businessID
        self.businessSnapshotData = businessSnapshotData
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.paymentTerms = paymentTerms
        self.notes = notes
        self.thankYou = thankYou
        self.termsAndConditions = termsAndConditions
        self.taxRate = taxRate
        self.discountAmount = discountAmount
        self.isPaid = isPaid
        self.documentType = documentType
        self.sourceBookingRequestId = sourceBookingRequestId
        self.sourceEstimateId = sourceEstimateId
        self.isRecurringGenerated = isRecurringGenerated
        self.recurringReviewedAt = recurringReviewedAt
        self.pdfRelativePath = pdfRelativePath
        self.invoiceTemplateKeyOverride = invoiceTemplateKeyOverride
        self.portalNeedsUpload = portalNeedsUpload
        self.portalUploadInFlight = portalUploadInFlight
        self.portalLastUploadedAtMs = portalLastUploadedAtMs
        self.portalLastUploadError = portalLastUploadError
        self.portalLastUploadedBlobUrl = portalLastUploadedBlobUrl
        self.portalLastUploadedHash = portalLastUploadedHash
        self.client = client
        self.clientID = client?.id
        self.job = job
        if let client {
            self.clientSnapshot = ClientSnapshot(
                name: client.name,
                email: client.email,
                phone: client.phone,
                address: client.address
            )
        }

        self.items = items
        for item in items { item.invoice = self }
    }

    func syncClientIDFromRelationship() {
        clientID = client?.id
        captureClientSnapshotIfNeeded()
    }

    var clientSnapshot: ClientSnapshot? {
        get {
            guard let data = clientSnapshotData else { return nil }
            return try? JSONDecoder().decode(ClientSnapshot.self, from: data)
        }
        set {
            guard let newValue else {
                clientSnapshotData = nil
                return
            }
            clientSnapshotData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The live client as a snapshot, if the relationship still points at one.
    var liveClientSnapshot: ClientSnapshot? {
        guard let client else { return nil }
        return ClientSnapshot(
            name: client.name,
            email: client.email,
            phone: client.phone,
            address: client.address
        )
    }

    /// Refresh the stored copy if policy says to. Cheap and idempotent — call it
    /// anywhere the invoice is about to be rendered, sent, or saved.
    @discardableResult
    func captureClientSnapshotIfNeeded() -> Bool {
        guard let next = ClientSnapshotPolicy.snapshotToStore(
            live: liveClientSnapshot,
            stored: clientSnapshot,
            isLocked: isBusinessInfoLocked
        ) else { return false }

        clientSnapshot = next
        return true
    }

    /// Who the document should name as the customer.
    var clientForRendering: ClientSnapshot? {
        ClientSnapshotPolicy.partyToRender(
            live: liveClientSnapshot,
            stored: clientSnapshot,
            isLocked: isBusinessInfoLocked
        )
    }

    /// The customer name for lists and detail headers.
    ///
    /// Prefers the live record, falls back to the snapshot, and only says
    /// "No Client" when the invoice genuinely never had one.
    var displayClientName: String {
        let name = (clientForRendering?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "No Client" : name
    }

    @MainActor
    var businessSnapshot: BusinessSnapshot? {
        get {
            guard let data = businessSnapshotData else { return nil }
            return try? JSONDecoder().decode(BusinessSnapshot.self, from: data)
        }
        set {
            guard let newValue else {
                businessSnapshotData = nil
                return
            }
            businessSnapshotData = try? JSONEncoder().encode(newValue)
        }
    }


    // MARK: - Money
    //
    // Integer cents are authoritative: they are what the client is charged, and
    // the only values sent to the portal or a payment provider. The Double
    // accessors below exist purely for display/formatting and are derived from
    // the cents, so a rendered total can never disagree with a charged total.
    //
    // Do not reintroduce a Double-first computation here. Summing unrounded line
    // totals and rounding once at the end produces a different answer than
    // rounding each line and summing — three items at $0.335 give 1.005 one way
    // and 1.02 the other — and that difference reaches customers as a PDF whose
    // total does not match their checkout page.

    var subtotal: Double { Self.dollars(subtotalCents) }
    var discountedSubtotal: Double { Self.dollars(discountedSubtotalCents) }
    var taxAmount: Double { Self.dollars(taxCents) }
    var total: Double { Self.dollars(totalCents) }

    private static func dollars(_ cents: Int) -> Double {
        Double(cents) / 100.0
    }

    var subtotalCents: Int {
        (items ?? []).reduce(0) { partial, item in
            partial + Int((item.lineTotal * 100.0).rounded())
        }
    }

    var discountCents: Int {
        max(0, Int((discountAmount * 100.0).rounded()))
    }

    var discountedSubtotalCents: Int {
        max(0, subtotalCents - discountCents)
    }

    var taxCents: Int {
        max(0, Int((Double(discountedSubtotalCents) * taxRate).rounded()))
    }

    var totalCents: Int {
        max(0, discountedSubtotalCents + taxCents)
    }

    var bookingDepositCents: Int {
        let cents = sourceBookingDepositAmountCents ?? 0
        return max(0, cents)
    }

    var remainingDueCents: Int {
        max(totalCents - bookingDepositCents, 0)
    }

    /// Everything paid toward this invoice: recorded payments plus a booking
    /// deposit. An invoice marked paid the old way (no payment rows) counts
    /// as paid in full.
    var paidCents: Int {
        let recorded = (payments ?? []).reduce(0) { $0 + max(0, $1.amountCents) }
        if isPaid && recorded == 0 { return totalCents }
        // A booking deposit counts only once it was actually paid.
        let depositPaid = (sourceBookingDepositPaidAtMs ?? 0) > 0 ? bookingDepositCents : 0
        return recorded + depositPaid
    }

    var balanceDueCents: Int {
        isPaid ? 0 : max(totalCents - paidCents, 0)
    }

    /// In front of the client: sent from the app, already published to the
    /// portal by an older build, or paid.
    var wasSent: Bool {
        sentAt != nil || portalLastUploadedAtMs != nil || isPaid
    }

    var isOverdue: Bool {
        wasSent && !isPaid && balanceDueCents > 0 && dueDate < Calendar.current.startOfDay(for: .now)
    }

    var overpaidCents: Int {
        max(bookingDepositCents - totalCents, 0)
    }
}

// MARK: - Invoice Snapshot / Finalization Helpers

extension Invoice {
    var trimmedInvoiceNumber: String {
        invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBusinessSnapshotLockReason: String {
        (businessSnapshotLockReason ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var hasBusinessSnapshotLockRecord: Bool {
        businessSnapshotLockedAt != nil || !normalizedBusinessSnapshotLockReason.isEmpty
    }

    var hasPortalUploadRecord: Bool {
        if portalLastUploadedAtMs != nil { return true }
        if portalLastUploadedHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if portalLastUploadedBlobUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return false
    }

    var estimateLocksBusinessSnapshot: Bool {
        guard documentType == "estimate" else { return false }
        let status = estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == "sent" || status == "accepted" || status == "declined"
    }

    var isBusinessInfoLocked: Bool {
        hasBusinessSnapshotLockRecord || isPaid || hasPortalUploadRecord || estimateLocksBusinessSnapshot
    }

    var canRefreshBusinessInfo: Bool {
        !isBusinessInfoLocked
    }

    var businessInfoLockStatusText: String? {
        guard isBusinessInfoLocked else { return nil }
        if normalizedBusinessSnapshotLockReason == "sent" || estimateLocksBusinessSnapshot {
            return "Business info locked on send"
        }
        return "Business info locked for historical record"
    }

    /// Whether this document is worth putting in front of a customer.
    ///
    /// A new invoice is created with one placeholder line at $0, and Send was
    /// enabled the moment it existed — so the app would happily email someone a
    /// bill for $0.00 with a line reading "Service". The amount is the entire
    /// point of the document; it has to be there before it goes out.
    var canBeSent: Bool {
        cannotBeSentReason == nil
    }

    /// Why Send is unavailable, phrased for the person reading it.
    var cannotBeSentReason: String? {
        let noun = documentType == "estimate" ? "estimate" : "invoice"

        if (items ?? []).isEmpty {
            return "Add what you're charging for before sending this \(noun)."
        }
        if totalCents <= 0 {
            return "This \(noun) totals $0.00. Set an amount on your line items before sending it."
        }
        return nil
    }

    /// An estimate that hasn't been sent. Drafts never leave the device:
    /// every portal write checks this, and an estimate reaches the client's
    /// portal only through Send Estimate (EstimateSendService). Before, the
    /// portal buttons, Done and the PDF upload all published drafts.
    var isUnsentEstimate: Bool {
        guard documentType == "estimate" else { return false }
        let status = estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["sent", "accepted", "declined"].contains(status)
    }

    /// A document that must not reach the client's portal yet: an estimate
    /// that wasn't sent, or an invoice that wasn't. Every portal write checks
    /// this; Send (EstimateSendService / InvoiceSendService) is the way in.
    var isUnsentDocument: Bool {
        documentType == "estimate" ? isUnsentEstimate : !wasSent
    }

    var isFinalized: Bool {
        isBusinessInfoLocked
    }

    var isDraftForSnapshotRefresh: Bool {
        canRefreshBusinessInfo
    }
}

// MARK: - Line Item

@Model
final class LineItem {
    var id: UUID = Foundation.UUID()

    var itemDescription: String = ""
    var quantity: Double = 1
    var unitPrice: Double = 0

    // ✅ Back-reference used in app logic (optional for CloudKit)
    var invoice: Invoice? = nil

    init(
        itemDescription: String = "",
        quantity: Double = 1,
        unitPrice: Double = 0
    ) {
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var lineTotal: Double { quantity * unitPrice }
}

// MARK: - Catalog Item

@Model
final class CatalogItem {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()

    var name: String = ""
    var details: String = ""
    var unitPrice: Double = 0
    var defaultQuantity: Double = 1
    var category: String = "General"

    init(
        name: String = "",
        details: String = "",
        unitPrice: Double = 0,
        defaultQuantity: Double = 1,
        category: String = "General"
    ) {
        self.name = name
        self.details = details
        self.unitPrice = unitPrice
        self.defaultQuantity = defaultQuantity
        self.category = category
    }
}

