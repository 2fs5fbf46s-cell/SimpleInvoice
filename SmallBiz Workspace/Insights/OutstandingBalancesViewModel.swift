import Foundation
import SwiftData
import Combine

struct InvoiceSnapshot: Sendable {
    let invoiceID: UUID
    let clientID: UUID?
    let clientName: String
    let amountCents: Int
    let dueDate: Date?
    let statusKey: String
    let isOverdue: Bool
}

struct ClientBalanceRowModel: Identifiable, Sendable {
    var id: UUID { clientID }
    let clientID: UUID
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
        let startedAt = Date()

        let modeKey = mode
        let modeLabel = modeKey == .overdueOnly ? "overdue" : "outstanding"

        #if DEBUG
        print("[OutstandingBalances] load start business=\(businessID.uuidString) mode=\(modeLabel)")
        #endif

        do {
            var fd = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { inv in
                    inv.businessID == businessID &&
                    inv.isPaid == false &&
                    inv.documentType != "estimate"
                },
                sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
            )
            fd.fetchLimit = 5000
            let invoices = try modelContext.fetch(fd)
            let now = Date()
            let snaps: [InvoiceSnapshot] = invoices.map { inv in
                let due = inv.dueDate
                let status: String = {
                    if inv.isPaid { return "PAID" }
                    let isDraft = (inv.items ?? []).isEmpty
                    return isDraft ? "DRAFT" : "UNPAID"
                }()
                let overdue = (due < now && (status == "UNPAID" || status == "SENT"))
                return InvoiceSnapshot(
                    invoiceID: inv.id,
                    clientID: inv.clientID,
                    clientName: (inv.client?.name ?? "Unknown Client"),
                    amountCents: max(0, inv.remainingDueCents),
                    dueDate: due,
                    statusKey: status,
                    isOverdue: overdue
                )
            }

            let computed: [ClientBalanceRowModel] = await Task.detached(priority: .userInitiated) {
                let unknownClientID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                var dict: [UUID: (name: String, count: Int, total: Int, ids: [UUID])] = [:]

                for s in snaps {
                    if modeKey == .overdueOnly, !s.isOverdue { continue }

                    let key = s.clientID ?? unknownClientID
                    if dict[key] == nil {
                        dict[key] = (s.clientName, 0, 0, [])
                    }
                    dict[key]!.count += 1
                    dict[key]!.total += s.amountCents
                    dict[key]!.ids.append(s.invoiceID)
                }

                return dict.map { (clientID, agg) in
                    ClientBalanceRowModel(
                        clientID: clientID,
                        clientName: agg.name,
                        invoiceCount: agg.count,
                        totalCents: agg.total,
                        invoiceIDs: agg.ids
                    )
                }.sorted { $0.totalCents > $1.totalCents }
            }.value

            guard self.loadToken == token else { return }

            self.rows = computed
            self.isLoading = false
            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[OutstandingBalances] load done rows=\(computed.count) loadMs=\(loadMs)")
            #endif
        } catch {
            guard self.loadToken == token else { return }
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[OutstandingBalances] load failed loadMs=\(loadMs) error=\(error)")
            #endif
        }
    }
}
