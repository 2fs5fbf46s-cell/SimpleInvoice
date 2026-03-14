//
//  ContractsHomeView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @State private var filter: HomeFilter = .all
    @State private var selectedContract: Contract? = nil
    @State private var loadedContracts: [Contract] = []
    @State private var loadedClients: [Client] = []
    @State private var loadedProfiles: [BusinessProfile] = []

    init(businessID: UUID? = nil) {
        self.businessID = businessID
    }

    private var effectiveBusinessID: UUID? {
        businessID
    }

    private var clientNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: loadedClients.map { ($0.id, $0.name) })
    }

    private enum HomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drafts = "Drafts"
        case active = "Active"
        var id: String { rawValue }
    }

    var body: some View {
        let currentContracts = loadedContracts
        let draftContracts = currentContracts.filter { $0.status == .draft }
        let activeContracts = currentContracts.filter { $0.status == .sent || $0.status == .signed }

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

                // MARK: - Create
                Section("Create") {
                    NavigationLink {
                        ContractTemplatePickerView(businessID: effectiveBusinessID)
                    } label: {
                        Label("Create From Template", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        ContractTemplatesView(businessID: effectiveBusinessID)
                    } label: {
                        Label("Manage Templates", systemImage: "doc.badge.gearshape")
                    }
                }

                Section {
                    Picker("", selection: $filter) {
                        ForEach(HomeFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Empty state (scoped)
                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view contracts.")
                    )
                } else if currentContracts.isEmpty {
                    ContentUnavailableView(
                        "No Contracts Yet",
                        systemImage: "doc.plaintext",
                        description: Text("Create a contract from a template, then export to PDF.")
                    )
                    NavigationLink {
                        ContractTemplatePickerView(businessID: effectiveBusinessID)
                    } label: {
                        Text("Create Contract")
                    }
                } else {

                    // MARK: - Drafts
                    if (filter == .all || filter == .drafts) && !draftContracts.isEmpty {
                        Section("Drafts") {
                            ForEach(draftContracts.prefix(10)) { contract in
                                Button {
                                    selectedContract = contract
                                } label: {
                                    contractRow(contract)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deleteIfDraft(contract)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Active / Signed
                    if (filter == .all || filter == .active) && !activeContracts.isEmpty {
                        Section("Active Contracts") {
                            ForEach(activeContracts.prefix(10)) { contract in
                                Button {
                                    selectedContract = contract
                                } label: {
                                    contractRow(contract)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }

                    // MARK: - View All
                    if currentContracts.count > 20 {
                        Section {
                            NavigationLink {
                                ContractsListView(businessID: effectiveBusinessID)
                            } label: {
                                Label("View All Contracts", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contracts")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedContract) { contract in
            ContractSummaryView(contract: contract)
        }
        .task {
            // Ensure built-in templates exist (safe to call repeatedly)
            ContractTemplateSeeder.seedIfNeeded(context: modelContext)
        }
        .task(id: effectiveBusinessID) {
            // Repair older contracts that were created with a random businessID,
            // then refresh the contracts snapshot used by this screen.
            repairOrphansIfNeeded()
            reloadData()
        }

        // Manual Test Steps:
        // 1) Switch business and verify drafts/active sections update without cross-business bleed.
        // 2) Open "View All Contracts" and confirm scoped list matches current business.
        // 3) Scroll contracts and open/close summaries repeatedly for navigation stability.
    }

    // MARK: - Row UI

    private func contractRow(_ contract: Contract) -> some View {
        let statusText = contract.status.rawValue.uppercased()
        let client = resolvedClientName(for: contract)
        let date = contract.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let category = contract.templateCategory.isEmpty ? "General" : contract.templateCategory
        let subtitle = "\(statusText) • \(client) • \(date) • \(category)"

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Contracts"))
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(
                title: contract.title.isEmpty ? "Contract" : contract.title,
                subtitle: subtitle
            )
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    // MARK: - Client name resolution (same logic as list)

    private func resolvedClientName(for contract: Contract) -> String {
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

    // MARK: - Deletes

    private func deleteIfDraft(_ contract: Contract) {
        guard contract.status == .draft else { return }
        modelContext.delete(contract)
        do {
            try modelContext.save()
            reloadData()
            Haptics.success()
        }
        catch {
            Haptics.error()
            print("Failed to delete draft contract: \(error)")
        }
    }

    // MARK: - Migration: Fix old random businessIDs

    private func repairOrphansIfNeeded() {
        guard let bizID = effectiveBusinessID else { return }

        // Known business IDs = anything you have a BusinessProfile for
        let knownBizIDs = Set(loadedProfiles.map { $0.businessID })
        guard !knownBizIDs.isEmpty else { return }

        var didChange = false

        for c in loadedContracts {
            // If contract.businessID isn’t one of our known businessIDs, it was likely created using the old UUID() fallback.
            if !knownBizIDs.contains(c.businessID) {
                c.businessID = bizID
                didChange = true
            }
        }

        guard didChange else { return }

        do { try modelContext.save() }
        catch { print("Failed to repair orphan contracts: \(error)") }
    }

    @MainActor
    private func reloadData() {
        do {
            let profileDescriptor = FetchDescriptor<BusinessProfile>(
                sortBy: [SortDescriptor(\BusinessProfile.name, order: .forward)]
            )
            loadedProfiles = try modelContext.fetch(profileDescriptor)

            guard let bizID = effectiveBusinessID else {
                loadedContracts = []
                loadedClients = []
                return
            }

            let contractDescriptor = FetchDescriptor<Contract>(
                predicate: #Predicate<Contract> { contract in
                    contract.businessID == bizID
                },
                sortBy: [SortDescriptor(\Contract.updatedAt, order: .reverse)]
            )
            loadedContracts = try modelContext.fetch(contractDescriptor)

            let clientDescriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { client in
                    client.businessID == bizID
                },
                sortBy: [SortDescriptor(\Client.name, order: .forward)]
            )
            loadedClients = try modelContext.fetch(clientDescriptor)
        } catch {
            print("Failed to load contracts home data: \(error)")
            loadedContracts = []
            loadedClients = []
        }
    }
}
