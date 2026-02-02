//
//  ContractsListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: \Contract.createdAt, order: .reverse)
    private var contracts: [Contract]

    @State private var searchText: String = ""
    @State private var filter: ContractFilter = .all
    @State private var blockedDeleteMessage: String? = nil

    private enum ContractFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case active = "Active"
        case signed = "Signed"
        case cancelled = "Cancelled"

        var id: String { rawValue }
    }

    // MARK: - Scoping

    private var scopedContracts: [Contract] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return contracts.filter { $0.businessID == bizID }
    }

    // MARK: - Client resolution (Job uses clientID, not relationship)

    private func clientName(for contract: Contract) -> String {
        if let name = contract.client?.name, !name.isEmpty { return name }
        if let name = contract.invoice?.client?.name, !name.isEmpty { return name }
        if let name = contract.estimate?.client?.name, !name.isEmpty { return name }

        if let job = contract.job {
            let allClients = (try? modelContext.fetch(FetchDescriptor<Client>())) ?? []
            return allClients.first(where: { $0.id == job.clientID })?.name ?? "No Client"
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
            case .active:
                return c.status == .sent
            case .signed:
                return c.status == .signed
            case .cancelled:
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
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            List {
                // Filter toggle (match other list screens)
                Section {
                    Picker("", selection: $filter) {
                        ForEach(ContractFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if scopedContracts.isEmpty {
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
                        NavigationLink {
                            ContractDetailView(contract: contract)
                        } label: {
                            row(contract)
                        }
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search contracts"
        )
        .settingsGear { BusinessProfileView() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CreateContractStartView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Can’t Delete", isPresented: Binding(
            get: { blockedDeleteMessage != nil },
            set: { if !$0 { blockedDeleteMessage = nil } }
        )) {
            Button("OK", role: .cancel) { blockedDeleteMessage = nil }
        } message: {
            Text(blockedDeleteMessage ?? "")
        }
    }

    // MARK: - Row UI (Option A parity)

    private func row(_ contract: Contract) -> some View {
        let statusText = statusText(for: contract)
        let chip = SBWTheme.chip(forStatus: statusText)
        let client = clientName(for: contract)

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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(contract.title.isEmpty ? "Contract" : contract.title)
                        .font(.headline)

                    Spacer()

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chip.fg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(chip.bg)
                        .clipShape(Capsule())
                }

                Text(client)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(contract.createdAt, style: .date)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(contract.templateCategory)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statusText(for contract: Contract) -> String {
        switch contract.status {
        case .draft: return "DRAFT"
        case .sent: return "SENT"
        case .signed: return "SIGNED"
        case .cancelled: return "CANCELLED"
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
