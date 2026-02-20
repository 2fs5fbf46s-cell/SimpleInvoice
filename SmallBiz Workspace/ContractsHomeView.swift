//
//  ContractsHomeView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    // All contracts, newest first
    @Query(sort: \Contract.updatedAt, order: .reverse)
    private var contracts: [Contract]

    // Used to detect valid businessIDs + migration safety
    @Query private var profiles: [BusinessProfile]

    @State private var filter: HomeFilter = .all
    @State private var selectedContract: Contract? = nil

    private enum HomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drafts = "Drafts"
        case active = "Active"
        var id: String { rawValue }
    }

    // MARK: - Scoping

    private var scopedContracts: [Contract] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return contracts.filter { $0.businessID == bizID }
    }

    // MARK: - Computed groups (scoped)

    private var draftContracts: [Contract] {
        scopedContracts.filter { $0.status == .draft }
    }

    private var activeContracts: [Contract] {
        scopedContracts.filter { $0.status == .sent || $0.status == .signed }
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

                // MARK: - Create
                Section("Create") {
                    NavigationLink {
                        ContractTemplatePickerView()
                    } label: {
                        Label("Create From Template", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        ContractTemplatesView()
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
                if activeBiz.activeBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view contracts.")
                    )
                } else if scopedContracts.isEmpty {
                    ContentUnavailableView(
                        "No Contracts Yet",
                        systemImage: "doc.plaintext",
                        description: Text("Create a contract from a template, then export to PDF.")
                    )
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
                    if scopedContracts.count > 20 {
                        Section {
                            NavigationLink {
                                ContractsListView()
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
            ContractDetailView(contract: contract)
        }
        .task {
            // Ensure built-in templates exist (safe to call repeatedly)
            ContractTemplateSeeder.seedIfNeeded(context: modelContext)

            // ✅ Repair older contracts that were created with a random businessID
            repairOrphansIfNeeded()
        }
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
            let allClients = (try? modelContext.fetch(FetchDescriptor<Client>())) ?? []
            return allClients.first(where: { $0.id == job.clientID })?.name ?? "No Client"
        }

        return "No Client"
    }

    // MARK: - Deletes

    private func deleteIfDraft(_ contract: Contract) {
        guard contract.status == .draft else { return }
        modelContext.delete(contract)
        do { try modelContext.save() }
        catch { print("Failed to delete draft contract: \(error)") }
    }

    // MARK: - Migration: Fix old random businessIDs

    private func repairOrphansIfNeeded() {
        guard let bizID = activeBiz.activeBusinessID else { return }

        // Known business IDs = anything you have a BusinessProfile for
        let knownBizIDs = Set(profiles.map { $0.businessID })
        guard !knownBizIDs.isEmpty else { return }

        var didChange = false

        for c in contracts {
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
}
