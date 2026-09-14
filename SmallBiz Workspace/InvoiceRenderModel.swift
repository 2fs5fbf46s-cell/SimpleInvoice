import Foundation

/// A plain, `Sendable` copy of everything the PDF generator reads off an invoice.
///
/// PDF rendering used to happen on the main actor, because the generator walked
/// SwiftData models directly and those are main-actor bound. A long invoice froze
/// the interface for the whole render, with no progress shown.
///
/// Taking a snapshot first decouples the two: gathering the data still touches the
/// models on the main actor, but the layout and rasterizing — which is where the
/// time goes — runs off it. It also makes the generator testable without a
/// `ModelContainer`.
///
/// Property names deliberately mirror `Invoice`, `LineItem` and `Client`, so the
/// generator reads the same expressions whichever it is handed.
struct InvoiceRenderModel: Sendable {

    struct Line: Sendable {
        let itemDescription: String
        let quantity: Double
        let unitPrice: Double
        let lineTotal: Double
    }

    struct Party: Sendable {
        let name: String
        let email: String
        let phone: String
        let address: String
    }

    let id: UUID
    let documentType: String
    let invoiceNumber: String
    let issueDate: Date
    let dueDate: Date
    let paymentTerms: String
    let notes: String
    let thankYou: String
    let termsAndConditions: String
    let taxRate: Double
    let discountAmount: Double
    let isPaid: Bool

    /// Derived from the authoritative integer cents on `Invoice`, so the rendered
    /// document shows the amount the customer is actually charged.
    let subtotal: Double
    let taxAmount: Double
    let total: Double

    /// Optional to match `Invoice.items`, so the generator's `?? []` still reads.
    let items: [Line]?
    let client: Party?
}

extension InvoiceRenderModel {
    /// Copy an invoice for rendering. Must run on the main actor — it reads
    /// SwiftData models — but it is the only part that has to.
    @MainActor
    init(invoice: Invoice) {
        self.id = invoice.id
        self.documentType = invoice.documentType
        self.invoiceNumber = invoice.invoiceNumber
        self.issueDate = invoice.issueDate
        self.dueDate = invoice.dueDate
        self.paymentTerms = invoice.paymentTerms
        self.notes = invoice.notes
        self.thankYou = invoice.thankYou
        self.termsAndConditions = invoice.termsAndConditions
        self.taxRate = invoice.taxRate
        self.discountAmount = invoice.discountAmount
        self.isPaid = invoice.isPaid

        self.subtotal = invoice.subtotal
        self.taxAmount = invoice.taxAmount
        self.total = invoice.total

        self.items = (invoice.items ?? []).map { item in
            Line(
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                lineTotal: item.lineTotal
            )
        }

        // Not `invoice.client` directly: a sent invoice must keep rendering the
        // name and address it was sent with, even after that client record is
        // deleted. `clientForRendering` resolves live-vs-snapshot; see
        // `ClientSnapshotPolicy`.
        if let party = invoice.clientForRendering, !party.isEmpty {
            self.client = Party(
                name: party.name,
                email: party.email,
                phone: party.phone,
                address: party.address
            )
        } else {
            self.client = nil
        }
    }
}
