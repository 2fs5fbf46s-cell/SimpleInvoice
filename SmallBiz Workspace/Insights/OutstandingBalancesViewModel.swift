import Foundation
import SwiftData
import Combine

enum OutstandingMode {
    case outstandingAll
    case overdueOnly
}

struct InvoiceSnapshot: Sendable {
    let invoiceID: UUID
    let clientID: UUID?
    let clientName: String
    let amountCents: Int
    let dueDate: Date?
    let statusKey: String
    let isOverdue: Bool
}

struct ClientBalanceRowModel: Identifiable, Hashable, Sendable {
    var id: UUID { clientID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    let clientID: UUID?
    let clientName: String
    let invoiceCount: Int
    let totalCents: Int
    let invoiceIDs: [UUID]
}

@MainActor
final class OutstandingBalancesViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var rows: [ClientBalanceRowModel] = []
    @Published var errorMessage: String? = nil

    private var loadToken = UUID()

    func load(modelContext: ModelContext, businessID: UUID, mode: OutstandingMode) async {
        let token = UUID()
        loadToken = token
        isLoading = true
        errorMessage = nil
        rows = []

        do {
            var fd = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { inv in
                    inv.businessID == businessID && inv.isPaid == false
                },
                sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
            )
            fd.fetchLimit = 5000

            let invoices = try modelContext.fetch(fd)

            let now = Date()
            let snaps: [InvoiceSnapshot] = invoices.compactMap { inv in
                let type = inv.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if type == "estimate" { return nil }

                let due = inv.dueDate
                let status: String = {
                    if inv.isPaid { return "PAID" }
                    let isDraft = (inv.items ?? []).isEmpty
                    return isDraft ? "DRAFT" : "UNPAID"
                }()
                let overdue = (due < now && (status == "UNPAID" || status == "SENT"))

                return InvoiceSnapshot(
                    invoiceID: inv.id,
                    clientID: inv.client?.id,
                    clientName: (inv.client?.name ?? "Unknown Client"),
                    amountCents: max(0, inv.remainingDueCents),
                    dueDate: due,
                    statusKey: status,
                    isOverdue: overdue
                )
            }

            let computed: [ClientBalanceRowModel] = await Task.detached(priority: .userInitiated) {
                var dict: [UUID?: (name: String, count: Int, total: Int, ids: [UUID])] = [:]

                for s in snaps {
                    if mode == .overdueOnly && !s.isOverdue { continue }

                    let key = s.clientID
                    if dict[key] == nil {
                        dict[key] = (s.clientName, 0, 0, [])
                    }
                    dict[key]!.count += 1
                    dict[key]!.total += s.amountCents
                    dict[key]!.ids.append(s.invoiceID)
                }

                let rows = dict.map { (clientID, agg) in
                    ClientBalanceRowModel(
                        clientID: clientID,
                        clientName: agg.name,
                        invoiceCount: agg.count,
                        totalCents: agg.total,
                        invoiceIDs: agg.ids
                    )
                }.sorted { $0.totalCents > $1.totalCents }

                return rows
            }.value

            guard self.loadToken == token else { return }

            self.rows = computed
            self.isLoading = false
        } catch {
            guard self.loadToken == token else { return }
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
}
