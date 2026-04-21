import SwiftData
import SwiftUI

struct SBWCardContainer<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SummaryKit.SummaryCard {
            content
        }
    }
}

struct SBWSectionHeaderRow: View {
    let title: String
    let subtitle: String?
    let status: String?

    init(title: String, subtitle: String? = nil, status: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    var body: some View {
        SummaryKit.SummaryHeader(title: title, subtitle: subtitle, status: status)
    }
}

struct SBWStatusPill: View {
    let text: String

    var body: some View {
        SummaryKit.StatusChip(text: text)
    }
}

struct InvoiceOverviewView: View {
    @Bindable var invoice: Invoice

    var body: some View {
        InvoiceDetailView(invoice: invoice)
    }
}

struct BookingOverviewView: View {
    let request: BookingRequestItem
    let onStatusChange: (String) -> Void

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
    }

    var body: some View {
        BookingDetailView(request: request, onStatusChange: onStatusChange)
    }
}

struct ContractBodyView: View {
    @Bindable var contract: Contract

    var body: some View {
        ContractDetailView(contract: contract)
    }
}

struct ContractActivityView: View {
    @Bindable var contract: Contract

    var body: some View {
        ContractDetailView(contract: contract)
    }
}

private struct ClientContractSelection: Identifiable, Hashable {
    let id: UUID
}

struct ClientContractsView: View {
    let businessID: UUID
    let clientID: UUID
    let clientName: String
    @Query private var contracts: [Contract]
    @State private var selectedContract: ClientContractSelection?

    init(businessID: UUID, clientID: UUID, clientName: String) {
        self.businessID = businessID
        self.clientID = clientID
        self.clientName = clientName
        _contracts = Query(
            filter: #Predicate<Contract> { contract in
                contract.businessID == businessID
            },
            sort: [SortDescriptor(\Contract.updatedAt, order: .reverse)]
        )
    }

    private var filteredContracts: [Contract] {
        contracts.filter { contract in
            contract.client?.id == clientID ||
            contract.invoice?.client?.id == clientID ||
            contract.estimate?.client?.id == clientID ||
            contract.job?.clientID == clientID
        }
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : clientName,
                    subtitle: "Contracts",
                    status: filteredContracts.isEmpty ? "EMPTY" : "\(filteredContracts.count) TOTAL"
                )
            }
            .listRowBackground(Color.clear)

            if filteredContracts.isEmpty {
                Text("No contracts found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredContracts) { contract in
                    Button {
                        selectedContract = ClientContractSelection(id: contract.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contract.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contract" : contract.title)
                                .font(.headline)
                            Text(contract.statusRaw.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Contracts")
        .navigationDestination(item: $selectedContract) { selection in
            ClientContractRouteView(contractID: selection.id)
        }
    }
}

private struct ClientContractRouteView: View {
    @Environment(\.modelContext) private var modelContext

    let contractID: UUID

    @State private var contract: Contract?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let contract {
                ContractSummaryView(contract: contract)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Load Contract",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading contract...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task(id: contractID) {
            do {
                let descriptor = FetchDescriptor<Contract>(
                    predicate: #Predicate<Contract> { contract in
                        contract.id == contractID
                    }
                )
                contract = try modelContext.fetch(descriptor).first
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
