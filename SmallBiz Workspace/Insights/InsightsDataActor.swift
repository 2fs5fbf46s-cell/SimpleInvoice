import Foundation
import SwiftData

enum OutstandingMode: String, Sendable {
    case outstandingAll
    case overdueOnly
}

struct InvoiceSnapshot: Sendable {
    let invoiceID: UUID
    let clientID: UUID
    let clientName: String
    let amountCents: Int
    let dueDate: Date?
    let documentType: String
    let isPaid: Bool
}

struct ClientBalanceRowModel: Identifiable, Sendable {
    let clientID: UUID
    let clientName: String
    let invoiceCount: Int
    let totalCents: Int

    var id: UUID { clientID }
}

@ModelActor
actor InsightsDataActor {
    private static let unknownClientID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    func fetchUnpaidInvoiceSnapshots(businessID: UUID) throws -> [InvoiceSnapshot] {
        var fd = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { inv in
                inv.businessID == businessID && inv.isPaid == false
            },
            sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
        )
        fd.fetchLimit = 5000

        let invoices = try modelContext.fetch(fd)

        return invoices.compactMap { inv in
            let type = inv.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if type == "estimate" { return nil }

            let clientID = inv.clientID ?? inv.client?.id ?? Self.unknownClientID
            let clientName = inv.client?.name ?? "Unknown Client"

            return InvoiceSnapshot(
                invoiceID: inv.id,
                clientID: clientID,
                clientName: clientName,
                amountCents: max(0, inv.remainingDueCents),
                dueDate: inv.dueDate,
                documentType: inv.documentType,
                isPaid: inv.isPaid
            )
        }
    }

    func fetchClientUnpaidInvoices(businessID: UUID, clientID: UUID, mode: OutstandingMode) throws -> [InvoiceSnapshot] {
        let snaps = try fetchUnpaidInvoiceSnapshots(businessID: businessID)
        let now = Date()

        return snaps.filter { snap in
            guard snap.clientID == clientID else { return false }
            if mode == .overdueOnly {
                guard let dueDate = snap.dueDate else { return false }
                return dueDate < now
            }
            return true
        }
    }
}
