import Foundation
import Combine
import SwiftData

@MainActor
final class OutstandingBalancesViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var rows: [ClientBalanceRowModel] = []
    @Published var errorMessage: String? = nil

    private var loadToken = UUID()
    private static let unknownClientID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    func load(modelContext: ModelContext, businessID: UUID, mode: OutstandingMode) async {
        let token = UUID()
        loadToken = token
        isLoading = true
        errorMessage = nil
        rows = []

        let startedAt = Date()

        #if DEBUG
        print("[OutstandingBalances] load start business=\(businessID.uuidString) mode=\(mode == .overdueOnly ? "overdue" : "outstanding")")
        #endif

        do {
            var fd = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID &&
                    invoice.isPaid == false &&
                    invoice.documentType != "estimate"
                }
            )
            fd.fetchLimit = 3000

            let invoices = try modelContext.fetch(fd)
            let now = Date()

            var grouped: [UUID: (name: String, count: Int, total: Int)] = [:]
            for invoice in invoices {
                if mode == .overdueOnly && !(invoice.dueDate < now) {
                    continue
                }

                let clientID = invoice.clientID ?? Self.unknownClientID
                let clientName = (invoice.client?.name ?? "Unknown Client")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let safeName = clientName.isEmpty ? "Unknown Client" : clientName

                if grouped[clientID] == nil {
                    grouped[clientID] = (safeName, 0, 0)
                }

                grouped[clientID]!.count += 1
                grouped[clientID]!.total += max(0, invoice.remainingDueCents)
            }

            guard loadToken == token else { return }

            let computed = grouped.map { (clientID, aggregate) in
                ClientBalanceRowModel(
                    clientID: clientID,
                    clientName: aggregate.name,
                    invoiceCount: aggregate.count,
                    totalCents: aggregate.total
                )
            }.sorted { $0.totalCents > $1.totalCents }

            rows = computed
            isLoading = false

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[OutstandingBalances] load done rows=\(computed.count) loadMs=\(loadMs)")
            #endif
        } catch {
            guard loadToken == token else { return }
            isLoading = false
            errorMessage = error.localizedDescription

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[OutstandingBalances] load failed loadMs=\(loadMs) error=\(error)")
            #endif
        }
    }
}
