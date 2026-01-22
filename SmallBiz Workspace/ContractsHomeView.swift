//
//  ContractsHomeView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractsHomeView: View {
    @Environment(\.modelContext) private var modelContext

    // All contracts, newest first
    @Query(sort: \Contract.updatedAt, order: .reverse)
    private var contracts: [Contract]

    @State private var filter: HomeFilter = .all

    private enum HomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drafts = "Drafts"
        case active = "Active"
        var id: String { rawValue }
    }

    var body: some View {
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

            // MARK: - Drafts
            if (filter == .all || filter == .drafts) && !draftContracts.isEmpty {
                Section("Drafts") {
                    ForEach(draftContracts.prefix(10)) { contract in
                        NavigationLink {
                            ContractDetailView(contract: contract)
                        } label: {
                            contractRow(contract)
                        }
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
                        NavigationLink {
                            ContractDetailView(contract: contract)
                        } label: {
                            contractRow(contract)
                        }
                    }
                }
            }

            // MARK: - View All
            if contracts.count > 20 {
                Section {
                    NavigationLink {
                        ContractsListView()
                    } label: {
                        Label("View All Contracts", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
        }
        .navigationTitle("Contracts")
        .task {
            // Ensure built-in templates exist (safe to call repeatedly)
            ContractTemplateSeeder.seedIfNeeded(context: modelContext)
        }
    }

    // MARK: - Computed groups

    private var draftContracts: [Contract] {
        contracts.filter { $0.status == .draft }
    }

    private var activeContracts: [Contract] {
        contracts.filter {
            $0.status == .sent || $0.status == .signed
        }
    }

    // MARK: - Row UI

    private func contractRow(_ contract: Contract) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contract.title.isEmpty ? "Contract" : contract.title)
                .font(.headline)

            HStack(spacing: 8) {
                Text(contract.templateCategory)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .clipShape(Capsule())

                Text(contract.status.rawValue.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(contract.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func statusLabel(_ status: ContractStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .signed: return "Signed"
        case .cancelled: return "Cancelled"
        }
    }


    private func deleteIfDraft(_ contract: Contract) {
        guard contract.status == .draft else { return }
        modelContext.delete(contract)
        do { try modelContext.save() }
        catch { print("Failed to delete draft contract: \(error)") }
    }
}
