import Combine
import SwiftUI
import SwiftData

/// Opens search from any tab. `AppTabView` owns the sheet.
@MainActor
final class GlobalSearchPresenter: ObservableObject {
    @Published var isPresented = false
}

/// The magnifying glass on every tab.
struct GlobalSearchButton: View {
    @EnvironmentObject private var presenter: GlobalSearchPresenter

    var body: some View {
        Button {
            Haptics.lightTap()
            presenter.isPresented = true
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search")
    }
}

/// One search across the whole business: clients, invoices, estimates, jobs,
/// contracts and expenses.
///
/// Each list had its own search, which only found what that list holds — to
/// find "the Smith job" you had to know it was a job, go to Work, pick Jobs,
/// then search. Records open here, the same screens the lists open.
struct GlobalSearchView: View {
    let businessID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var query = ""
    @State private var searchFocused = false
    @State private var documents: [SearchDocument] = []
    @State private var opened: SearchDocument?
    @State private var recentIDs: [String] = []

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyQueryContent
                } else if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(sections, id: \.kind) { section in
                        Section {
                            ForEach(section.documents) { row($0) }
                        } header: {
                            Text(section.totalCount > section.documents.count
                                 ? "\(section.kind.sectionTitle) · first \(section.documents.count) of \(section.totalCount)"
                                 : section.kind.sectionTitle)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                isPresented: $searchFocused,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Names, numbers, amounts, places"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $opened) { destination($0) }
            .onAppear {
                reload()
                recentIDs = RecentSearchRecords.ids(for: businessID)
                searchFocused = true
            }
            // Back from a record: it may have been renamed, paid or deleted.
            .onChange(of: opened) { _, now in if now == nil { reload() } }
        }
    }

    private var sections: [SearchEngine.Section] {
        SearchEngine.sections(for: query, in: documents)
    }

    @ViewBuilder
    private var emptyQueryContent: some View {
        let recents = recentIDs.compactMap { id in documents.first { $0.id == id } }
        if recents.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Search your whole business")
                        .font(.headline)
                    Text("Clients, invoices, estimates, jobs, contracts and expenses. Try a name, an invoice number, an amount or a street.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        } else {
            Section("Recent") {
                ForEach(recents) { row($0) }
            }
        }
    }

    private func row(_ document: SearchDocument) -> some View {
        Button {
            RecentSearchRecords.add(document.id, for: businessID)
            recentIDs = RecentSearchRecords.ids(for: businessID)
            opened = document
        } label: {
            HStack(spacing: 12) {
                Image(systemName: document.kind.systemImage)
                    .font(.body)
                    .foregroundStyle(SBWTheme.brand)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !document.subtitle.isEmpty {
                        Text(document.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(document.kind.sectionTitle)
    }

    @ViewBuilder
    private func destination(_ document: SearchDocument) -> some View {
        let id = document.recordID
        switch document.kind {
        case .client:
            if let client = fetch(Client.self, #Predicate { $0.id == id }) { ClientDetailView(client: client) } else { missing }
        case .invoice, .estimate:
            if let invoice = fetch(Invoice.self, #Predicate { $0.id == id }) { InvoiceOverviewView(invoice: invoice) } else { missing }
        case .job:
            if let job = fetch(Job.self, #Predicate { $0.id == id }) { JobDetailView(job: job) } else { missing }
        case .contract:
            if let contract = fetch(Contract.self, #Predicate { $0.id == id }) { ContractDetailView(contract: contract) } else { missing }
        case .expense:
            if let expense = fetch(Expense.self, #Predicate { $0.id == id }) { ExpenseFormView(expense: expense, isDraft: false) } else { missing }
        }
    }

    private var missing: some View {
        ContentUnavailableView("This was deleted", systemImage: "trash", description: Text("It's no longer in your records."))
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func reload() {
        documents = SearchDocuments.all(businessID: businessID, context: modelContext)
    }
}

/// The records last opened from search, newest first, per business.
enum RecentSearchRecords {
    static let limit = 8

    static func ids(for businessID: UUID) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(businessID)) ?? []
    }

    static func add(_ id: String, for businessID: UUID) {
        var ids = ids(for: businessID).filter { $0 != id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(limit)), forKey: key(businessID))
    }

    private static func key(_ businessID: UUID) -> String {
        "sbw.search.recent.\(businessID.uuidString)"
    }
}
