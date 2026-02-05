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

    // Booking Portal
    var bookingSlug: String = ""
    var bookingEnabled: Bool = true
    var bookingHoursText: String = ""
    var bookingInstructions: String = ""

    var logoData: Data? = nil
   


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
        bookingSlug: String = "",
        bookingEnabled: Bool = true,
        bookingHoursText: String = "",
        bookingInstructions: String = "",
        logoData: Data? = nil,
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
        self.bookingSlug = bookingSlug
        self.bookingEnabled = bookingEnabled
        self.bookingHoursText = bookingHoursText
        self.bookingInstructions = bookingInstructions
        self.logoData = logoData
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
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    

    // ✅ ARRAY-side inverses for CloudKit (avoid circular macro issues)
    @Relationship(inverse: \Invoice.client)
    var invoices: [Invoice]? = []
    @Relationship(inverse: \ClientAttachment.client) var attachments: [ClientAttachment]? = nil
    @Relationship(inverse: \Booking.client) var bookings: [Booking]? = nil
    


    @Relationship(inverse: \Contract.client)
    var contracts: [Contract]? = []

    init(
        businessID: UUID = UUID(),
        name: String = "",
        email: String = "",
        phone: String = "",
        address: String = ""
    ) {
        self.businessID = businessID
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
    }
    
}

// MARK: - Invoice

@Model
final class Invoice {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()

    var businessSnapshotData: Data? = nil

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

    @Relationship(inverse: \InvoiceAttachment.invoice) var attachments: [InvoiceAttachment]? = nil
    
    
    // MARK: - Estimate workflow
    var estimateStatus: String = "draft"     // draft | sent | accepted | declined
    var estimateAcceptedAt: Date? = nil


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
        self.client = client
        self.job = job

        self.items = items
        for item in items { item.invoice = self }
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


    var subtotal: Double { (items ?? []).reduce(0) { $0 + $1.lineTotal } }
    var discountedSubtotal: Double { max(0, subtotal - discountAmount) }
    var taxAmount: Double { discountedSubtotal * taxRate }
    var total: Double { discountedSubtotal + taxAmount }
}

// MARK: - Invoice Snapshot / Finalization Helpers

extension Invoice {
    var trimmedInvoiceNumber: String {
        invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFinalized: Bool {
        if documentType == "invoice" {
            return !trimmedInvoiceNumber.isEmpty
        }

        let status = estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == "sent" || status == "accepted"
    }

    var isDraftForSnapshotRefresh: Bool {
        if documentType == "invoice" {
            return trimmedInvoiceNumber.isEmpty && businessSnapshotData == nil
        }

        let status = estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == "draft" && businessSnapshotData == nil
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

@Model
final class Booking {
    var id: UUID = UUID()

    var title: String = ""
    var notes: String = ""

    var startDate: Date = Date()
    var endDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    // scheduled | completed | canceled
    var status: String = "scheduled"

    var locationName: String = ""

    // ✅ Inverse lives on Client.bookings
    var client: Client? = nil

    init(
        title: String = "",
        notes: String = "",
        startDate: Date = Date(),
        endDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date(),
        status: String = "scheduled",
        locationName: String = "",
        client: Client? = nil
    ) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.locationName = locationName
        self.client = client
    }
}
