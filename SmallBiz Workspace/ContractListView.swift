//
//  ContractListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Filters for the contracts list. Open is what still needs something: drafts
/// to send and contracts waiting on a signature.
private enum ContractListFilter: String, CaseIterable {
    case open = "Open"
    case signed = "Signed"
    case canceled = "Canceled"
    case all = "All"
}

private struct ContractGroup: Identifiable {
    let title: String
    let contracts: [Contract]
    var id: String { title }
}

/// Every contract, grouped by what it needs.
///
/// This replaces two lists: a home screen that never showed canceled
/// contracts, capped each section at 10 and linked to the full list only
/// past 20, and that full list, which called canceled contracts "Expired",
/// deleted drafts without asking, and didn't open a contract you'd just made.
struct ContractListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var contracts: [Contract]

    @State private var searchText = ""
    @State private var filter: ContractListFilter = .open
    @State private var selectedContract: Contract? = nil
    @State private var showNewContract = false
    @State private var showTemplates = false
    @State private var pendingDelete: Contract? = nil
    @State private var pendingCancel: Contract? = nil

    init(businessID: UUID?) {
        self.businessID = businessID
        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _contracts = Query(
            filter: #Predicate<Contract> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Contract.updatedAt, order: .reverse)]
        )
    }

    // MARK: - Data

    private var searched: [Contract] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return contracts }
        return contracts.filter {
            $0.title.lowercased().contains(q)
                || $0.displayClientName.lowercased().contains(q)
                || $0.templateName.lowercased().contains(q)
        }
    }

    private var groups: [ContractGroup] {
        let items = searched
        let waiting = items
            .filter { $0.status == .sent }
            .sorted { ($0.sentAt ?? $0.updatedAt) < ($1.sentAt ?? $1.updatedAt) }
        let drafts = items.filter { $0.status == .draft }
        let signed = items
            .filter { $0.status == .signed }
            .sorted { ($0.signedAt ?? $0.updatedAt) > ($1.signedAt ?? $1.updatedAt) }
        let canceled = items.filter { $0.status == .cancelled }

        let all: [ContractGroup] = [
            ContractGroup(title: "Waiting for signature", contracts: waiting),
            ContractGroup(title: "Drafts", contracts: drafts),
            ContractGroup(title: "Signed", contracts: signed),
            ContractGroup(title: "Canceled", contracts: canceled),
        ]
        let wanted: Set<String>
        switch filter {
        case .open: wanted = ["Waiting for signature", "Drafts"]
        case .signed: wanted = ["Signed"]
        case .canceled: wanted = ["Canceled"]
        case .all: wanted = Set(all.map(\.title))
        }
        return all.filter { wanted.contains($0.title) && !$0.contracts.isEmpty }
    }

    private func count(_ option: ContractListFilter) -> Int {
        switch option {
        case .open: return contracts.filter { $0.status == .draft || $0.status == .sent }.count
        case .signed: return contracts.filter { $0.status == .signed }.count
        case .canceled: return contracts.filter { $0.status == .cancelled }.count
        case .all: return contracts.count
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search title, client, template", text: $searchText)
                            .textInputAutocapitalization(.never)
                        Button {
                            showTemplates = true
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(SBWTheme.brandBlue)
                        .accessibilityLabel("Templates")
                        Button {
                            Haptics.lightTap()
                            showNewContract = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Contract")
                    }
                    .padding(.vertical, 4)

                    SBWFilterChips(
                        options: ContractListFilter.allCases,
                        title: { option in
                            let n = count(option)
                            return option == .all || n == 0 ? option.rawValue : "\(option.rawValue) \(n)"
                        },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if businessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to see its contracts.")
                    )
                } else if groups.isEmpty {
                    Section { emptyState }
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.contracts) { contract in
                                Button {
                                    selectedContract = contract
                                } label: {
                                    ContractListRow(contract: contract)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    trailingSwipe(for: contract)
                                }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contracts")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $selectedContract) { ContractDetailView(contract: $0) }
        .navigationDestination(isPresented: $showTemplates) { ContractTemplatesView(businessID: businessID) }
        .sheet(isPresented: $showNewContract) {
            NavigationStack {
                CreateContractStartView(
                    businessID: businessID,
                    onCreated: { contract in
                        showNewContract = false
                        filter = .open
                        DispatchQueue.main.async { selectedContract = contract }
                    },
                    onCancel: { showNewContract = false }
                )
            }
        }
        .confirmationDialog(
            "Delete this draft?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { contract in
            Button("Delete Draft", role: .destructive) {
                modelContext.delete(contract)
                try? modelContext.save()
                pendingDelete = nil
            }
            Button("Keep It", role: .cancel) { pendingDelete = nil }
        } message: { contract in
            Text("\"\(contract.title.isEmpty ? "Contract" : contract.title)\" was never sent. This can't be undone.")
        }
        .confirmationDialog(
            "Cancel this contract?",
            isPresented: Binding(get: { pendingCancel != nil }, set: { if !$0 { pendingCancel = nil } }),
            titleVisibility: .visible,
            presenting: pendingCancel
        ) { contract in
            Button("Cancel Contract", role: .destructive) {
                pendingCancel = nil
                Task { await ContractLifecycle.cancel(contract, context: modelContext) }
            }
            Button("Keep It", role: .cancel) { pendingCancel = nil }
        } message: { contract in
            Text(contract.status == .sent
                 ? "\(contract.displayClientName) will see it as canceled and won't be able to sign it."
                 : "It stays in your records. You can reopen it later.")
        }
        .task { ContractTemplateSeeder.seedIfNeeded(context: modelContext) }
        .refreshable { await ContractActivityPullService.pull(context: modelContext, businessID: businessID) }
    }

    @ViewBuilder
    private func trailingSwipe(for contract: Contract) -> some View {
        if ContractLifecycle.canDelete(contract) {
            Button(role: .destructive) { pendingDelete = contract } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        } else if contract.status == .sent || contract.status == .draft {
            Button { pendingCancel = contract } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 8) {
            Image(systemName: "signature")
                .font(.title2)
                .foregroundStyle(.secondary)
            if isSearching {
                Text("No contracts match \"\(searchText)\"")
                    .font(.headline)
            } else if contracts.isEmpty {
                Text("Start your first contract")
                    .font(.headline)
                Text("Pick a template, fill in the client, and send it to sign.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button { showNewContract = true } label: { Label("New Contract", systemImage: "plus") }
                    .sbwProminentButton()
                    .padding(.top, 4)
            } else {
                Text(filter == .open ? "Nothing waiting on you" : "No \(filter.rawValue.lowercased()) contracts")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct ContractListRow: View {
    let contract: Contract

    private var status: ContractDisplayStatus { ContractDisplayStatus(contract) }

    private var subtitle: String {
        var parts: [String] = []
        let name = contract.displayClientName
        parts.append(name == "No Client" ? "No client" : name)
        switch status {
        case .draft:
            parts.append("edited \(contract.updatedAt.formatted(.relative(presentation: .named)))")
        case .sent:
            if let sent = contract.sentAt {
                parts.append("sent \(sent.formatted(date: .abbreviated, time: .omitted))")
            }
        case .signed:
            if let signed = contract.signedAt {
                parts.append("signed \(signed.formatted(date: .abbreviated, time: .omitted))")
            }
        case .canceled:
            if let canceled = contract.canceledAt {
                parts.append("canceled \(canceled.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .signed ? "checkmark.seal" : "signature")
                .font(.subheadline)
                .foregroundStyle(status == .signed ? SBWTheme.brandGreen : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(contract.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled contract" : contract.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(status.label)
                .font(.caption2.weight(.semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(status.foreground.opacity(0.15)))
                .foregroundStyle(status.foreground)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ContractListView: Equatable {
    static func == (lhs: ContractListView, rhs: ContractListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
