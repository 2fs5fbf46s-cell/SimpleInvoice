import OSLog
//
//  InvoiceListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

private struct InvoiceListSelection: Identifiable, Hashable {
    let id: UUID
}

private struct InvoiceListInvoiceRouteView: View {
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
                    "Couldn’t Load Invoice",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading invoice...")
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
                loadError = invoice == nil ? "Invoice not found." : nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

/// Which invoices the list shows. The old filters didn't mean what they
/// said — "Draft" was "has no line items", "Overdue" included empty drafts.
enum InvoiceListFilter: String, CaseIterable, Identifiable, Hashable {
    case open = "Open"
    case overdue = "Overdue"
    case drafts = "Drafts"
    case paid = "Paid"
    case all = "All"

    var id: String { rawValue }
}

private enum InvoiceListToolbarRoute: Hashable, Identifiable {
    case businessProfile
    case savedItems

    var id: String {
        switch self {
        case .businessProfile: return "businessProfile"
        case .savedItems: return "savedItems"
        }
    }
}

/// Where an invoice is, for the list: the same stages as the invoice screen.
private enum InvoiceListStage {
    case draft, sent, overdue, partPaid, paid

    init(_ invoice: Invoice) {
        if invoice.isPaid || (invoice.wasSent && invoice.totalCents > 0 && invoice.balanceDueCents == 0) {
            self = .paid
        } else if !invoice.wasSent {
            self = .draft
        } else if invoice.isOverdue {
            self = .overdue
        } else if (invoice.payments ?? []).contains(where: { $0.amountCents > 0 }) {
            self = .partPaid
        } else {
            self = .sent
        }
    }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .overdue: return "Overdue"
        case .partPaid: return "Part paid"
        case .paid: return "Paid"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .secondary
        case .sent: return SBWTheme.brand
        case .overdue: return .red
        case .partPaid: return SBWTheme.attention
        case .paid: return SBWTheme.success
        }
    }
}

/// The invoice list, grouped by what needs doing: overdue first, then what
/// you're waiting on, then drafts, then what's paid — with the money owed
/// and overdue totals on top.
struct InvoiceListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var invoices: [Invoice]
    @Query private var profiles: [BusinessProfile]

    @State private var showingNewInvoice = false
    @State private var showingTemplates = false
    @State private var showingInvoiceSettings = false
    @State private var showingRecurringSchedules = false
    @State private var toolbarRoute: InvoiceListToolbarRoute?

    @State private var selectedInvoice: InvoiceListSelection? = nil
    @State private var filter: InvoiceListFilter
    @State private var searchText: String = ""

    @State private var pendingDelete: Invoice? = nil
    @State private var paymentInvoice: Invoice? = nil
    @State private var reminderInvoice: Invoice? = nil
    @State private var listNotice: String? = nil

    /// Set by the Money tiles ("Overdue" opens the Overdue filter).
    private var requestedFilter: InvoiceListFilter?

    init(businessID: UUID? = nil, initialFilter: InvoiceListFilter? = nil, requestedFilter: InvoiceListFilter? = nil) {
        self.businessID = businessID
        self.requestedFilter = requestedFilter
        _filter = State(initialValue: initialFilter ?? .open)
        if let businessID {
            _invoices = Query(
                filter: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID && invoice.documentType != "estimate"
                },
                sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
            _profiles = Query(filter: #Predicate<BusinessProfile> { $0.businessID == businessID })
        } else {
            _invoices = Query(
                filter: #Predicate<Invoice> { $0.documentType != "estimate" },
                sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
            _profiles = Query()
        }
    }

    private struct InvoiceGroup: Identifiable {
        let title: String
        let invoices: [Invoice]
        var id: String { title }
    }

    private var scoped: [Invoice] {
        invoices.scoped(to: businessID)
    }

    private var searched: [Invoice] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return scoped }
        return scoped.filter { invoice in
            invoice.invoiceNumber.localizedCaseInsensitiveContains(q)
                || invoice.displayClientName.localizedCaseInsensitiveContains(q)
                || (invoice.job?.title.localizedCaseInsensitiveContains(q) ?? false)
                || invoice.notes.localizedCaseInsensitiveContains(q)
                || (invoice.items ?? []).contains { $0.itemDescription.localizedCaseInsensitiveContains(q) }
        }
    }

    private var groups: [InvoiceGroup] {
        let all = searched
        func stage(_ invoice: Invoice) -> InvoiceListStage { InvoiceListStage(invoice) }
        let overdue = all.filter { stage($0) == .overdue }.sorted { $0.dueDate < $1.dueDate }
        let waiting = all.filter { [.sent, .partPaid].contains(stage($0)) }.sorted { $0.dueDate < $1.dueDate }
        let drafts = all.filter { stage($0) == .draft }
        let paid = all.filter { stage($0) == .paid }.sorted { paidDate($0) > paidDate($1) }

        let result: [InvoiceGroup]
        switch filter {
        case .open:
            result = [InvoiceGroup(title: "Overdue", invoices: overdue), InvoiceGroup(title: "Waiting on payment", invoices: waiting)]
        case .overdue:
            result = [InvoiceGroup(title: "Overdue", invoices: overdue)]
        case .drafts:
            result = [InvoiceGroup(title: "Drafts", invoices: drafts)]
        case .paid:
            result = [InvoiceGroup(title: "Paid", invoices: paid)]
        case .all:
            result = [
                InvoiceGroup(title: "Overdue", invoices: overdue),
                InvoiceGroup(title: "Waiting on payment", invoices: waiting),
                InvoiceGroup(title: "Drafts", invoices: drafts),
                InvoiceGroup(title: "Paid", invoices: paid),
            ]
        }
        return result.filter { !$0.invoices.isEmpty }
    }

    private func paidDate(_ invoice: Invoice) -> Date {
        (invoice.payments ?? []).map(\.paidAt).max() ?? invoice.issueDate
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search invoices, clients, items", text: $searchText)
                            .textInputAutocapitalization(.never)
                        Button {
                            Haptics.lightTap()
                            showingNewInvoice = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brand.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Invoice")
                    }
                    .padding(.vertical, 4)

                    SBWFilterChips(
                        options: InvoiceListFilter.allCases,
                        title: { $0.rawValue },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if let listNotice {
                    Section {
                        Text(listNotice)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if businessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view invoices.")
                    )
                } else if groups.isEmpty {
                    Section { emptyState }
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.invoices) { invoice in
                                Button {
                                    selectedInvoice = InvoiceListSelection(id: invoice.id)
                                } label: {
                                    InvoiceListRow(invoice: invoice)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    leadingSwipe(for: invoice)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = invoice
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button { duplicateAndOpen(invoice) } label: {
                                        Label("Duplicate Invoice", systemImage: "doc.on.doc")
                                    }
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
        .navigationTitle("Invoices")
        .onChange(of: requestedFilter) { _, requested in
            if let requested { filter = requested }
        }
        .onAppear { if let requestedFilter { filter = requestedFilter } }
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { showingRecurringSchedules = true } label: {
                        Label("Recurring Invoices", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { showingTemplates = true } label: {
                        Label("Invoice Templates", systemImage: "square.grid.2x2")
                    }
                    Button { toolbarRoute = .savedItems } label: {
                        Label("Saved Items", systemImage: "tray")
                    }
                    Divider()
                    Button { showingInvoiceSettings = true } label: {
                        Label("Invoice Settings", systemImage: "slider.horizontal.3")
                    }
                    Button { toolbarRoute = .businessProfile } label: {
                        Label("Business Profile", systemImage: "building.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Invoice Menu")
            }
        }
        .confirmationDialog(
            "Delete invoice \(pendingDelete?.invoiceNumber ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Invoice", role: .destructive) {
                if let invoice = pendingDelete { delete(invoice) }
                pendingDelete = nil
            }
            Button("Keep Invoice", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.wasSent == true
                 ? "Your client already has this invoice; it stays in their portal. This can't be undone."
                 : "This can't be undone.")
        }
        .confirmationDialog(
            "Send a reminder?",
            isPresented: Binding(get: { reminderInvoice != nil }, set: { if !$0 { reminderInvoice = nil } }),
            titleVisibility: .visible,
            presenting: reminderInvoice
        ) { invoice in
            Button("Send Reminder") { remind(invoice) }
            Button("Cancel", role: .cancel) {}
        } message: { invoice in
            Text(InvoiceSendService.confirmationMessage(for: invoice, kind: .reminder))
        }
        .sheet(item: $paymentInvoice) { invoice in
            RecordPaymentSheet(invoice: invoice)
        }
        .sheet(isPresented: $showingNewInvoice) {
            NewInvoiceView(businessID: businessID) { invoice in
                selectedInvoice = InvoiceListSelection(id: invoice.id)
            }
        }
        .sheet(isPresented: $showingTemplates) {
            NavigationStack {
                InvoiceTemplatePickerView(
                    templates: builtInTemplates(),
                    onUse: { template in
                        createInvoiceFromTemplate(template)
                    }
                )
                .navigationTitle("Templates")
                .navigationBarTitleDisplayMode(.inline)
                .sbwNavigationBarBackdrop()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingTemplates = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingInvoiceSettings) {
            NavigationStack {
                InvoiceSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingInvoiceSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingRecurringSchedules) {
            NavigationStack {
                RecurringInvoiceScheduleListView(businessID: businessID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingRecurringSchedules = false }
                        }
                    }
            }
        }
        .navigationDestination(item: $selectedInvoice) { selection in
            InvoiceListInvoiceRouteView(invoiceID: selection.id)
        }
        .navigationDestination(item: $toolbarRoute) { route in
            switch route {
            case .businessProfile:
                BusinessProfileView()
            case .savedItems:
                CatalogItemListView()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 8) {
            Image(systemName: "doc.plaintext")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(isSearching ? "No invoices match \"\(searchText)\"" : emptyTitle)
                .font(.headline)
            if !isSearching && (filter == .open || filter == .all) {
                Text(filter == .open ? "Invoices you've sent and not been paid for show up here." : "Create your first invoice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button { showingNewInvoice = true } label: { Label("New Invoice", systemImage: "plus") }
                    .sbwProminentButton()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyTitle: String {
        switch filter {
        case .open: return "Nothing waiting on payment"
        case .overdue: return "Nothing overdue"
        case .drafts: return "No drafts"
        case .paid: return "No paid invoices yet"
        case .all: return "No invoices yet"
        }
    }

    @ViewBuilder
    private func leadingSwipe(for invoice: Invoice) -> some View {
        switch InvoiceListStage(invoice) {
        case .overdue:
            Button { reminderInvoice = invoice } label: { Label("Remind", systemImage: "bell") }
                .tint(.red)
            Button { paymentInvoice = invoice } label: { Label("Payment", systemImage: "banknote") }
                .tint(SBWTheme.success)
        case .sent, .partPaid, .draft:
            if invoice.totalCents > 0 {
                Button { paymentInvoice = invoice } label: { Label("Payment", systemImage: "banknote") }
                    .tint(SBWTheme.success)
            }
        case .paid:
            EmptyView()
        }
    }

    private func remind(_ invoice: Invoice) {
        let businessName = profiles.first?.name
        Task {
            do {
                switch try await InvoiceSendService.send(invoice, kind: .reminder, context: modelContext, businessName: businessName) {
                case .emailed(let email):
                    Haptics.success()
                    listNotice = "Reminder sent to \(email)."
                case .publishedNotEmailed:
                    listNotice = "The reminder didn't send. Open the invoice to try again."
                }
            } catch {
                listNotice = error.localizedDescription
            }
        }
    }

    private func delete(_ invoice: Invoice) {
        modelContext.delete(invoice)
        do {
            try modelContext.save()
            Haptics.success()
        } catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to delete invoice: \(error)")
        }
    }

    private func duplicateAndOpen(_ invoice: Invoice) {
        do {
            let copy = try InvoiceDuplicationService.duplicate(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            Haptics.success()
            selectedInvoice = InvoiceListSelection(id: copy.id)
        } catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to duplicate invoice: \(error)")
        }
    }
}

/// Who it's for, what it is and when it's due, with the amount and status.
private struct InvoiceListRow: View {
    let invoice: Invoice

    private var stage: InvoiceListStage { InvoiceListStage(invoice) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(stage == .overdue ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(InvoicePaymentService.currency(stage == .paid ? invoice.totalCents : invoice.balanceDueCents))
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let client = invoice.displayClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !client.isEmpty, client != "No Client" { return client }
        return invoice.invoiceNumber.isEmpty ? "Invoice" : "Invoice \(invoice.invoiceNumber)"
    }

    private var subtitle: String {
        let number = invoice.invoiceNumber.isEmpty ? nil : invoice.invoiceNumber
        let job = invoice.job?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let when: String
        let calendar = Calendar.current
        switch stage {
        case .paid:
            let paid = (invoice.payments ?? []).map(\.paidAt).max()
            when = paid.map { "paid \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "paid"
        case .overdue:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: invoice.dueDate), to: calendar.startOfDay(for: .now)).day ?? 0
            when = "\(days) day\(days == 1 ? "" : "s") late"
        case .draft:
            when = "not sent"
        case .sent, .partPaid:
            when = "due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))" + (invoice.viewedAt != nil ? " · viewed" : "")
        }
        return [number, (job?.isEmpty == false ? job : nil), when].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Templates (unchanged)

private extension InvoiceListView {

    func builtInTemplates() -> [InvoiceTemplate] {
        [
            InvoiceTemplate(
                title: "Basic Service",
                description: "One service line item with standard terms.",
                defaultLineItems: [
                    InvoiceTemplateLineItem(description: "Service", quantity: 1, unitPrice: 0)
                ],
                defaultPaymentTerms: "Net 14",
                defaultNotes: "Thanks for your business!",
                defaultTaxRate: 0,
                defaultDiscount: 0
            ),
            InvoiceTemplate(
                title: "Photography Session",
                description: "Session fee + standard note (edit pricing later).",
                defaultLineItems: [
                    InvoiceTemplateLineItem(description: "Photography Session", quantity: 1, unitPrice: 0)
                ],
                defaultPaymentTerms: "Due on receipt",
                defaultNotes: "Thank you for booking!",
                defaultTaxRate: 0,
                defaultDiscount: 0
            )
        ]
    }

    func createInvoiceFromTemplate(_ template: InvoiceTemplate) {
        do {
            guard let bizID = businessID else {
                SBWLog.ui.problem("❌ No active business selected")
                return
            }

            let profile: BusinessProfile = profiles.first(where: { $0.businessID == bizID }) ?? {
                let created = BusinessProfile(businessID: bizID)
                modelContext.insert(created)
                return created
            }()

            let newNumber = InvoiceNumberGenerator.generateNextNumber(profile: profile)

            let invoice = Invoice(
                businessID: bizID,
                invoiceNumber: newNumber,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                paymentTerms: template.defaultPaymentTerms,
                notes: template.defaultNotes,
                taxRate: template.defaultTaxRate,
                discountAmount: template.defaultDiscount,
                isPaid: false,
                documentType: "invoice",
                client: nil,
                items: []
            )

            if invoice.items == nil { invoice.items = [] }

            for li in template.defaultLineItems {
                let newItem = LineItem(
                    itemDescription: li.description,
                    quantity: li.quantity,
                    unitPrice: li.unitPrice
                )
                invoice.items?.append(newItem)
                newItem.invoice = invoice
            }

            modelContext.insert(invoice)
            try modelContext.save()
            Haptics.success()

            showingTemplates = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                selectedInvoice = InvoiceListSelection(id: invoice.id)
            }
        } catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to create invoice from template: \(error)")
        }
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension InvoiceListView: Equatable {
    static func == (lhs: InvoiceListView, rhs: InvoiceListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
