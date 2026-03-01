import Foundation
import SwiftData
import Combine

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
            let dataActor = InsightsDataActor(modelContainer: modelContext.container)
            let snaps = try await dataActor.fetchUnpaidInvoiceSnapshots(businessID: businessID)
            let now = Date()

            let computed: [ClientBalanceRowModel] = await Task.detached(priority: .userInitiated) {
                var dict: [UUID: (name: String, count: Int, total: Int)] = [:]

                for snap in snaps {
                    if modeKey == .overdueOnly {
                        guard let dueDate = snap.dueDate, dueDate < now else { continue }
                    }

                    if dict[snap.clientID] == nil {
                        dict[snap.clientID] = (snap.clientName, 0, 0)
                    }
                    dict[snap.clientID]!.count += 1
                    dict[snap.clientID]!.total += snap.amountCents
                }

                return dict.map { (clientID, agg) in
                    ClientBalanceRowModel(
                        clientID: clientID,
                        clientName: agg.name,
                        invoiceCount: agg.count,
                        totalCents: agg.total
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
