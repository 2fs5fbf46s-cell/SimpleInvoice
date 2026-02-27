//
//  ContractsListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    private let businessID: UUID?

    @Query(sort: \Contract.createdAt, order: .reverse)
    private var contracts: [Contract]
    @Query private var clients: [Client]

    @State private var searchText: String = ""
    @State private var filter: ContractFilter = .all
    @State private var blockedDeleteMessage: String? = nil
    @State private var selectedContract: Contract? = nil
    @State private var showCreateContract = false

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _contracts = Query(
                filter: #Predicate<Contract> { contract in
                    contract.businessID == businessID
                },
                sort: [SortDescriptor(\Contract.createdAt, order: .reverse)]
            )
            _clients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == businessID
                },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )
        } else {
            _contracts = Query(sort: [SortDescriptor(\Contract.createdAt, order: .reverse)])
            _clients = Query(sort: [SortDescriptor(\Client.name, order: .forward)])
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID ?? activeBiz.activeBusinessID
    }

    private enum ContractFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case sent = "Sent"
        case signed = "Signed"
        case expired = "Expired"

        var id: String { rawValue }
    }

    // MARK: - Scoping

    private var scopedContracts: [Contract] {
        guard let bizID = effectiveBusinessID else { return [] }
        return contracts.filter { $0.businessID == bizID }
    }

    private var clientNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.name) })
    }

    // MARK: - Client resolution (Job uses clientID, not relationship)

    private func clientName(for contract: Contract) -> String {
        if let name = contract.client?.name, !name.isEmpty { return name }
        if let name = contract.invoice?.client?.name, !name.isEmpty { return name }
        if let name = contract.estimate?.client?.name, !name.isEmpty { return name }

        if let job = contract.job {
            if let id = job.clientID, let name = clientNameByID[id], !name.isEmpty {
                return name
            }
            return "No Client"
        }

        return "No Client"
    }

    // MARK: - Filtering

    private var filteredContracts: [Contract] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        func matchesSearch(_ c: Contract) -> Bool {
            guard !q.isEmpty else { return true }
            let client = clientName(for: c)

            return c.title.localizedCaseInsensitiveContains(q)
            || client.localizedCaseInsensitiveContains(q)
            || c.templateCategory.localizedCaseInsensitiveContains(q)
            || c.templateName.localizedCaseInsensitiveContains(q)
        }

        func matchesFilter(_ c: Contract) -> Bool {
            switch filter {
            case .all:
                return true
            case .draft:
                return c.status == .draft
            case .sent:
                return c.status == .sent
            case .signed:
                return c.status == .signed
            case .expired:
                return c.status == .cancelled
            }
        }

        return scopedContracts.filter { matchesFilter($0) && matchesSearch($0) }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search contracts", text: $searchText)
                            .textInputAutocapitalization(.never)

                        Button {
                            showCreateContract = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.2)))
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ContractFilter.allCases) { f in
                                Button {
                                    filter = f
                                } label: {
                                    Text(f.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(filter == f ? SBWTheme.brandBlue.opacity(0.22) : Color.primary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view contracts.")
                    )
                } else if scopedContracts.isEmpty {
                    ContentUnavailableView(
                        "No Contracts Yet",
                        systemImage: "doc.plaintext",
                        description: Text("Create contracts from templates, then export to PDF.")
                    )
                } else if filteredContracts.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different filter or search term.")
                    )
                } else {
                    ForEach(filteredContracts) { contract in
                        Button {
                            selectedContract = contract
                        } label: {
                            row(contract)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                attemptDelete(contract)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteContracts)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contracts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .navigationDestination(item: $selectedContract) { contract in
            ContractSummaryView(contract: contract)
        }
        .navigationDestination(isPresented: $showCreateContract) {
            CreateContractStartView()
        }
        .alert("Can’t Delete", isPresented: Binding(
            get: { blockedDeleteMessage != nil },
            set: { if !$0 { blockedDeleteMessage = nil } }
        )) {
            Button("OK", role: .cancel) { blockedDeleteMessage = nil }
        } message: {
            Text(blockedDeleteMessage ?? "")
        }

        // Manual Test Steps:
        // 1) Switch business and confirm contracts list shows only scoped data.
        // 2) Open contract summary, close, reopen quickly; selection should remain correct.
        // 3) Scroll long list and verify row interactions stay smooth.
    }

    // MARK: - Row UI (Option A parity)

    private func row(_ contract: Contract) -> some View {
        let statusText = statusText(for: contract)
        let client = clientName(for: contract)
        let date = contract.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let category = contract.templateCategory.isEmpty ? "General" : contract.templateCategory
        let subtitle = "\(client) • \(date) • \(category)"

        return HStack(alignment: .top, spacing: 12) {
            // Leading icon chip (matches other tiles/lists)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Contracts"))
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contract.title.isEmpty ? "Contract" : contract.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    SBWStatusPill(text: statusText)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private func statusText(for contract: Contract) -> String {
        switch contract.status {
        case .draft: return "DRAFT"
        case .sent: return "SENT"
        case .signed: return "SIGNED"
        case .cancelled: return "EXPIRED"
        }
    }

    // MARK: - Deletes (draft-only)

    private func deleteContracts(at offsets: IndexSet) {
        var blockedCount = 0

        for index in offsets {
            guard index < filteredContracts.count else { continue }
            let c = filteredContracts[index]

            if c.status == .draft {
                modelContext.delete(c)
            } else {
                blockedCount += 1
            }
        }

        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }

        if blockedCount > 0 {
            blockedDeleteMessage = "Only Draft contracts can be deleted. \(blockedCount) contract(s) weren’t deleted because they aren’t Draft."
        }
    }

    private func attemptDelete(_ contract: Contract) {
        guard contract.status == .draft else {
            blockedDeleteMessage = "Only Draft contracts can be deleted. Change status back to Draft if you need to remove it."
            return
        }

        modelContext.delete(contract)

        do { try modelContext.save() }
        catch { print("Failed to delete contract: \(error)") }
    }
}
