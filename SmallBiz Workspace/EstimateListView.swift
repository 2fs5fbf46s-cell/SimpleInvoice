import OSLog
//
//  EstimateListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

private struct EstimateListSelection: Identifiable, Hashable {
    let id: UUID
}

private struct EstimateListInvoiceRouteView: View {
    @Environment(\.modelContext) private var modelContext

    let invoiceID: UUID

    @State private var invoice: Invoice?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let invoice {
                InvoiceOverviewView(invoice: invoice)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Load Estimate",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading estimate...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task(id: invoiceID) {
            do {
                let descriptor = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.id == invoiceID
                    }
                )
                invoice = try modelContext.fetch(descriptor).first
                loadError = invoice == nil ? "Estimate not found." : nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

private enum EstimateListToolbarRoute: Hashable, Identifiable {
    case businessProfile
    case savedItems

    var id: String {
        switch self {
        case .businessProfile: return "businessProfile"
        case .savedItems: return "savedItems"
        }
    }
}

struct EstimateListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var invoices: [Invoice]


    @State private var selectedEstimate: EstimateListSelection? = nil

    @State private var pendingDelete: Invoice? = nil

    // Open detail after creation
    @State private var showingNewEstimate = false
    @State private var newEstimate: Invoice? = nil

    // Create sheet fields
    @State private var showingCreateEstimate = false
    @State private var draftName: String = ""
    @State private var draftClient: Client? = nil
    @State private var showingEstimateSettings = false
    @State private var toolbarRoute: EstimateListToolbarRoute?

    // MARK: - Filters
    private enum Filter: String, CaseIterable, Identifiable {
        case open = "Open"
        case accepted = "Accepted"
        case declined = "Declined"
        case all = "All"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .open
    @State private var searchText: String = ""
    @State private var isRefreshingFromPortal = false

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _invoices = Query(
                filter: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID
                },
                sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
        } else {
            _invoices = Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID
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
                        TextField("Search estimates", text: $searchText)
                            .textInputAutocapitalization(.never)

                        Button {
                            Haptics.lightTap()
                            draftName = ""
                            draftClient = nil
                            showingCreateEstimate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.2)))
                        }
                    }
                }

                Section {
                    estimateTiles
                        .buttonStyle(.plain)

                    SBWFilterChips(
                        options: Filter.allCases,
                        title: { option in
                            let n = count(option)
                            return option == .all || n == 0 ? option.rawValue : "\(option.rawValue) \(n)"
                        },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                // MARK: - Content
                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view estimates.")
                    )
                } else if groups.isEmpty {
                    let isFiltered = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || filter != .all
                    SBWEmptyState(
                        title: filter == .open && searchText.isEmpty ? "Nothing waiting on a client" : "No Estimates",
                        message: SBWEmptyStateCopy.message(
                            noun: "estimate",
                            pluralNoun: "estimates",
                            isFiltered: isFiltered
                        ),
                        systemImage: "doc.text",
                        actionTitle: "Create Estimate",
                        action: {
                            draftName = ""
                            draftClient = nil
                            showingCreateEstimate = true
                        },
                        secondaryTitle: isFiltered ? "Show All" : nil,
                        secondaryAction: isFiltered ? {
                            searchText = ""
                            filter = .all
                        } : nil
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.estimates) { estimate in
                                Button {
                                    selectedEstimate = EstimateListSelection(id: estimate.id)
                                } label: {
                                    EstimateListRow(estimate: estimate)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = estimate
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await EstimateAcceptancePullService.pullAndMaterialize(context: modelContext, businessID: effectiveBusinessID)
                EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            }
        }
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()

        // MARK: - Toolbar (matches InvoiceListView style)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        toolbarRoute = .businessProfile
                    } label: {
                        Label("Business Profile", systemImage: "gearshape")
                    }

                    Button {
                        toolbarRoute = .savedItems
                    } label: {
                        Label("Saved Items", systemImage: "tray")
                    }

                    Button {
                        showingEstimateSettings = true
                    } label: {
                        Label("Estimate Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Estimate Menu")
            }
        }

        .navigationDestination(item: $selectedEstimate) { selection in
            EstimateListInvoiceRouteView(invoiceID: selection.id)
        }
        .navigationDestination(item: $toolbarRoute) { route in
            switch route {
            case .businessProfile:
                BusinessProfileView()
            case .savedItems:
                CatalogItemListView()
            }
        }

        .confirmationDialog(
            "Delete this estimate?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { estimate in
            Button("Delete Estimate", role: .destructive) {
                modelContext.delete(estimate)
                do { try modelContext.save() }
                catch { SBWLog.ui.problem("Failed to save deletes: \(error)") }
                pendingDelete = nil
            }
            Button("Keep It", role: .cancel) { pendingDelete = nil }
        } message: { estimate in
            Text(estimate.wasSent
                 ? "The client already has it. Their link stops working."
                 : "It was never sent.")
        }

        // MARK: - Create sheet (name + client)
        .sheet(isPresented: $showingCreateEstimate) {
            NewEstimateSheet(
                name: $draftName,
                client: $draftClient,
                businessID: businessID,
                onCancel: { showingCreateEstimate = false },
                onCreate: { createEstimateFromDraft() }
            )
        }
        .sheet(isPresented: $showingEstimateSettings) {
            NavigationStack {
                EstimateDefaultsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingEstimateSettings = false }
                        }
                    }
            }
        }

        // MARK: - New Estimate Detail Sheet (supports Cancel-delete behavior)
        .sheet(isPresented: $showingNewEstimate, onDismiss: {
            newEstimate = nil
        }) {

            NavigationStack {
                if let inv = newEstimate {
                    InvoiceDetailView(invoice: inv)
                        .interactiveDismissDisabled()
                        .navigationTitle("New Estimate")
                        .navigationBarTitleDisplayMode(.inline)
                        .sbwNavigationBarBackdrop()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") {
                                    cancelAndDeleteIfDraftIsEmpty(forceDelete: true)
                                    showingNewEstimate = false
                                }
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                if let estimate = newEstimate {
                                        PortalAutoSyncService.markInvoiceNeedsUploadIfChanged(invoice: estimate, business: nil)
                                        try? modelContext.save()
                                        let estimateID = estimate.id
                                        Task {
                                            _ = await PortalAutoSyncService.uploadEstimate(
                                                estimateId: estimateID,
                                                context: modelContext
                                            )
                                        }
                                    }
                                    Haptics.success()
                                    showingNewEstimate = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                } else {
                    ContentUnavailableView("Unable to open estimate", systemImage: "exclamationmark.triangle")
                }
            }
        }
        // One batched pull for every estimate's decision. This used to ask
        // the server about each estimate in turn, every time the Estimates
        // tab was opened.
        .task(id: effectiveBusinessID) {
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            await EstimateAcceptancePullService.pullAndMaterialize(context: modelContext, businessID: effectiveBusinessID)
        }
    }

    // MARK: - Data (scoped + filtered)

    private var scopedInvoices: [Invoice] {
        invoices.scoped(to: effectiveBusinessID)
    }

    private var estimates: [Invoice] {
        scopedInvoices.filter { $0.documentType == "estimate" }
    }

    private var searched: [Invoice] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return estimates }
        return estimates.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(q)
                || $0.displayClientName.localizedCaseInsensitiveContains(q)
                || ($0.job?.title.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.items ?? []).contains { $0.itemDescription.localizedCaseInsensitiveContains(q) }
        }
    }

    private struct EstimateGroup: Identifiable {
        let title: String
        let estimates: [Invoice]
        var id: String { title }
    }

    private var groups: [EstimateGroup] {
        let all = searched
        let waiting = all.filter { EstimateStage($0) == .waiting }
            .sorted { ($0.sentAt ?? $0.issueDate) < ($1.sentAt ?? $1.issueDate) }
        let drafts = all.filter { EstimateStage($0) == .draft }
        let accepted = all.filter { EstimateStage($0) == .accepted }
            .sorted { ($0.estimateAcceptedAt ?? $0.issueDate) > ($1.estimateAcceptedAt ?? $1.issueDate) }
        let declined = all.filter { EstimateStage($0) == .declined }
        let result: [EstimateGroup]
        switch filter {
        case .open:
            result = [.init(title: "Waiting on the client", estimates: waiting), .init(title: "Not sent yet", estimates: drafts)]
        case .accepted:
            result = [.init(title: "Accepted", estimates: accepted)]
        case .declined:
            result = [.init(title: "Declined", estimates: declined)]
        case .all:
            result = [
                .init(title: "Waiting on the client", estimates: waiting),
                .init(title: "Not sent yet", estimates: drafts),
                .init(title: "Accepted", estimates: accepted),
                .init(title: "Declined", estimates: declined),
            ]
        }
        return result.filter { !$0.estimates.isEmpty }
    }

    private func count(_ option: Filter) -> Int {
        switch option {
        case .open: return estimates.filter { [.waiting, .draft].contains(EstimateStage($0)) }.count
        default: return 0
        }
    }

    private var estimateTiles: some View {
        let waiting = estimates.filter { EstimateStage($0) == .waiting }
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let accepted = estimates.filter { EstimateStage($0) == .accepted && ($0.estimateAcceptedAt ?? .distantPast) >= since }
        let drafts = estimates.filter { EstimateStage($0) == .draft }
        return HStack(spacing: 8) {
            EstimateTile(title: "Waiting",
                         value: InvoicePaymentService.currency(waiting.reduce(0) { $0 + $1.totalCents }),
                         detail: "\(waiting.count) estimate\(waiting.count == 1 ? "" : "s")") { filter = .open }
            EstimateTile(title: "Accepted",
                         value: InvoicePaymentService.currency(accepted.reduce(0) { $0 + $1.totalCents }),
                         detail: "last 30 days") { filter = .accepted }
            EstimateTile(title: "Not sent", value: "\(drafts.count)",
                         detail: drafts.count == 1 ? "draft" : "drafts") { filter = .open }
        }
    }


    // MARK: - Create

    private func createEstimateFromDraft() {
        do {
            guard let bizID = effectiveBusinessID else {
                SBWLog.ui.problem("❌ No active business selected")
                return
            }

            let estimate = try EstimateDrafts.make(
                name: draftName,
                client: draftClient,
                businessID: bizID,
                context: modelContext
            )

            showingCreateEstimate = false
            newEstimate = estimate
            showingNewEstimate = true
        } catch {
            SBWLog.ui.problem("Failed to create estimate: \(error)")
        }
    }

    // MARK: - Cancel behavior (delete empty draft)

    private func cancelAndDeleteIfDraftIsEmpty(forceDelete: Bool = false) {
        guard let inv = newEstimate else { return }
        guard inv.documentType == "estimate" else { newEstimate = nil; return }

        let hasClient = (inv.client != nil)
        let hasNotes = !inv.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasItems = !((inv.items ?? []).isEmpty)
        let hasMoney = inv.total != 0
        let statusNotDraft = EstimateStage(inv) != .draft

        let isEmptyDraft = !(hasClient || hasNotes || hasItems || hasMoney || statusNotDraft)

        if forceDelete || isEmptyDraft {
            modelContext.delete(inv)
            do { try modelContext.save() }
            catch { SBWLog.ui.problem("Failed to save cancel delete: \(error)") }
        }

        newEstimate = nil
    }

}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension EstimateListView: Equatable {
    static func == (lhs: EstimateListView, rhs: EstimateListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}

/// Where an estimate stands, from the client's side: not sent, waiting on
/// them, or decided. The list used to show "SENT"/"DRAFT" in capitals while
/// every other list says "Sent"/"Draft".
enum EstimateStage: Equatable {
    case draft, waiting, accepted, declined

    init(_ estimate: Invoice) {
        switch estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "accepted": self = .accepted
        case "declined": self = .declined
        case "sent": self = .waiting
        default: self = estimate.wasSent ? .waiting : .draft
        }
    }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .waiting: return "Waiting"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .secondary
        case .waiting: return .orange
        case .accepted: return .green
        case .declined: return .red
        }
    }
}

private struct EstimateListRow: View {
    let estimate: Invoice

    private var title: String {
        let job = (estimate.job?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstItem = (estimate.items ?? []).first?.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let what = job.isEmpty ? firstItem : job
        let client = estimate.displayClientName
        if what.isEmpty { return client }
        return client.isEmpty ? what : "\(what) · \(client)"
    }

    private var detail: String {
        var parts = [ClientWorkItem.documentName(estimate)]
        switch EstimateStage(estimate) {
        case .draft:
            parts.append("not sent")
        case .waiting:
            if let sent = estimate.sentAt {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: sent), to: Calendar.current.startOfDay(for: .now)).day ?? 0
                parts.append(days <= 0 ? "sent today" : "sent \(days) day\(days == 1 ? "" : "s") ago")
            } else {
                parts.append("sent")
            }
            if estimate.viewedAt != nil { parts.append("viewed") }
        case .accepted:
            if let at = estimate.estimateAcceptedAt { parts.append("accepted \(at.formatted(date: .abbreviated, time: .omitted))") }
        case .declined:
            if let at = estimate.estimateDeclinedAt { parts.append("declined \(at.formatted(date: .abbreviated, time: .omitted))") }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let stage = EstimateStage(estimate)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(InvoicePaymentService.currency(estimate.totalCents))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(stage.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(stage.color.opacity(0.15)))
                    .foregroundStyle(stage.color)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct EstimateTile: View {
    let title: String
    let value: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }
}
