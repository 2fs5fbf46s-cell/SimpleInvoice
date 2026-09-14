import SwiftUI
import SwiftData

private enum ClientContractSummaryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case sent = "Sent"
    case signed = "Signed"
    case expired = "Expired"

    var id: String { rawValue }

    func matches(_ contract: Contract) -> Bool {
        switch self {
        case .all:
            return true
        case .draft:
            return contract.status == .draft
        case .sent:
            return contract.status == .sent
        case .signed:
            return contract.status == .signed
        case .expired:
            return contract.status == .cancelled
        }
    }
}

struct ClientContractStatusTotals: Equatable {
    let draft: Int
    let sent: Int
    let signed: Int
    let expired: Int

    var total: Int {
        draft + sent + signed + expired
    }
}

enum ClientContractSummaryLogic {
    static func visibleContracts(in contracts: [Contract], businessID: UUID, clientID: UUID) -> [Contract] {
        contracts.filter { contract in
            isContract(contract, scopedTo: businessID, clientID: clientID)
        }
    }

    static func isContract(_ contract: Contract, scopedTo businessID: UUID, clientID: UUID) -> Bool {
        contract.businessID == businessID && belongsToClient(contract, clientID: clientID)
    }

    static func belongsToClient(_ contract: Contract, clientID: UUID) -> Bool {
        if contract.client?.id == clientID { return true }
        if contract.invoice?.client?.id == clientID || contract.invoice?.clientID == clientID { return true }
        if contract.estimate?.client?.id == clientID || contract.estimate?.clientID == clientID { return true }
        if contract.job?.clientID == clientID { return true }
        return false
    }

    static func statusTotals(for contracts: [Contract]) -> ClientContractStatusTotals {
        ClientContractStatusTotals(
            draft: contracts.filter { $0.status == .draft }.count,
            sent: contracts.filter { $0.status == .sent }.count,
            signed: contracts.filter { $0.status == .signed }.count,
            expired: contracts.filter { $0.status == .cancelled }.count
        )
    }

    static func statusText(for contract: Contract) -> String {
        switch contract.status {
        case .draft:
            return "DRAFT"
        case .sent:
            return "SENT"
        case .signed:
            return "SIGNED"
        case .cancelled:
            return "EXPIRED"
        }
    }
}

private struct ClientContractSummaryRowModel: Identifiable {
    let contract: Contract
    let title: String
    let statusText: String
    let detail: String
    let context: String

    var id: UUID { contract.id }
}

private struct ClientContractSelection: Identifiable, Hashable {
    let id: UUID
}

struct ClientContractsView: View {
    let businessID: UUID
    let clientID: UUID
    let clientName: String

    @Query private var contracts: [Contract]

    @State private var filter: ClientContractSummaryFilter = .all
    @State private var searchText = ""
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

    private var clientTitle: String {
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }

    private var clientContracts: [Contract] {
        ClientContractSummaryLogic.visibleContracts(
            in: contracts,
            businessID: businessID,
            clientID: clientID
        )
    }

    private var filteredContracts: [Contract] {
        let statusFiltered = clientContracts.filter { filter.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return statusFiltered }

        return statusFiltered.filter { contract in
            contract.title.localizedCaseInsensitiveContains(query) ||
            contract.templateName.localizedCaseInsensitiveContains(query) ||
            contract.templateCategory.localizedCaseInsensitiveContains(query) ||
            contract.renderedBody.localizedCaseInsensitiveContains(query) ||
            ClientContractSummaryLogic.statusText(for: contract).localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleRows: [ClientContractSummaryRowModel] {
        filteredContracts.map(makeRowModel(for:))
    }

    private var statusTotals: ClientContractStatusTotals {
        ClientContractSummaryLogic.statusTotals(for: clientContracts)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                summarySection
                filtersSection
                contractsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("All Contracts")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $selectedContract) { selection in
            ClientContractRouteView(
                contractID: selection.id,
                businessID: businessID,
                clientID: clientID
            )
        }
    }

    private var summarySection: some View {
        Section {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientTitle,
                    subtitle: "Contract Summary",
                    status: statusTotals.total == 0 ? "EMPTY" : "\(statusTotals.total) TOTAL"
                )

                metricRow(label: "Draft", value: "\(statusTotals.draft)")
                metricRow(label: "Sent", value: "\(statusTotals.sent)")
                metricRow(label: "Signed", value: "\(statusTotals.signed)")
                metricRow(label: "Expired", value: "\(statusTotals.expired)")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var filtersSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this client's contracts", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ClientContractSummaryFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                Text(option.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(filter == option ? SBWTheme.brandBlue.opacity(0.22) : Color.primary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var contractsSection: some View {
        Section("Contracts") {
            if visibleRows.isEmpty {
                ContentUnavailableView(
                    statusTotals.total == 0 ? "No contracts for this client" : "No matching contracts",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(statusTotals.total == 0
                        ? "Create a contract for this client to see it here."
                        : "Try a different filter or search term.")
                )
            } else {
                ForEach(visibleRows) { row in
                    Button {
                        selectedContract = ClientContractSelection(id: row.contract.id)
                    } label: {
                        contractRow(row)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        SummaryKit.SummaryKeyValueRow(label: label, value: value)
    }

    private func contractRow(_ row: ClientContractSummaryRowModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Contracts"))
                Image(systemName: "doc.text")
                    .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(row.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    SBWStatusPill(text: row.statusText)
                }

                Text(row.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(row.context)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 68, alignment: .topLeading)
    }

    private func makeRowModel(for contract: Contract) -> ClientContractSummaryRowModel {
        let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedText = contract.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let createdText = contract.createdAt.formatted(date: .abbreviated, time: .omitted)
        let detail = "Updated \(updatedText) \u{2022} Created \(createdText)"

        let templateName = contract.templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateCategory = contract.templateCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let context: String
        if !templateName.isEmpty && !templateCategory.isEmpty {
            context = "\(templateName) \u{2022} \(templateCategory)"
        } else if !templateName.isEmpty {
            context = templateName
        } else if !templateCategory.isEmpty {
            context = templateCategory
        } else {
            context = "General contract"
        }

        return ClientContractSummaryRowModel(
            contract: contract,
            title: title.isEmpty ? "Contract" : title,
            statusText: ClientContractSummaryLogic.statusText(for: contract),
            detail: detail,
            context: context
        )
    }
}

private struct ClientContractRouteView: View {
    @Environment(\.modelContext) private var modelContext

    let contractID: UUID
    let businessID: UUID
    let clientID: UUID

    @State private var contract: Contract?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let contract {
                ContractSummaryView(contract: contract)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't Load Contract",
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
            contract = nil
            loadError = nil

            do {
                let descriptor = FetchDescriptor<Contract>(
                    predicate: #Predicate<Contract> { contract in
                        contract.id == contractID && contract.businessID == businessID
                    }
                )

                guard let fetchedContract = try modelContext.fetch(descriptor).first else {
                    loadError = "The selected contract was not found for this business."
                    return
                }

                guard ClientContractSummaryLogic.isContract(fetchedContract, scopedTo: businessID, clientID: clientID) else {
                    loadError = "The selected contract does not belong to this client."
                    return
                }

                contract = fetchedContract
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
