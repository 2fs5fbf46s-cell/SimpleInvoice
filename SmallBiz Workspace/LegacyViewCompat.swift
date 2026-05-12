import SwiftData
import SwiftUI

struct SBWCardContainer<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SummaryKit.SummaryCard {
            content
        }
    }
}

struct SBWSectionHeaderRow: View {
    let title: String
    let subtitle: String?
    let status: String?

    init(title: String, subtitle: String? = nil, status: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    var body: some View {
        SummaryKit.SummaryHeader(title: title, subtitle: subtitle, status: status)
    }
}

struct SBWStatusPill: View {
    let text: String

    var body: some View {
        SummaryKit.StatusChip(text: text)
    }
}

struct InvoiceOverviewView: View {
    @Bindable var invoice: Invoice

    var body: some View {
        InvoiceOverviewSummaryView(invoice: invoice)
    }
}

private struct InvoiceOverviewSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]
    @Bindable var invoice: Invoice

    @State private var expandedSection: InvoiceOverviewSection? = nil
    @State private var shareItems: [Any]? = nil
    @State private var exportError: String? = nil
    @State private var convertedInvoice: Invoice? = nil
    @State private var detailInvoice: Invoice? = nil
    @State private var previewPDFURL: URL? = nil

    private enum InvoiceOverviewSection: Hashable {
        case items
        case payments
        case attachments
        case activity
        case advanced
    }

    private var titleText: String {
        if invoice.documentType == "estimate" {
            return "Estimate Summary"
        }
        return "Invoice Summary"
    }

    private var statusText: String {
        if invoice.documentType == "estimate" {
            let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return status.isEmpty ? "DRAFT" : status
        }
        if invoice.isPaid { return "PAID" }
        if invoice.dueDate < .now { return "OVERDUE" }
        return "UNPAID"
    }

    private var numberText: String {
        let trimmed = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Draft" : trimmed
    }

    private var itemCount: Int {
        (invoice.items ?? []).count
    }

    private var attachmentCount: Int {
        invoice.attachments?.count ?? 0
    }

    private var amountText: String {
        invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    private var dueLabel: String {
        invoice.documentType == "estimate" ? "Valid Until" : "Due"
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: "\(invoice.documentType == "estimate" ? "Estimate" : "Invoice") \(numberText)",
                    subtitle: "Summary",
                    status: statusText
                )
                SummaryKit.SummaryKeyValueRow(label: "Amount", value: amountText)
                SummaryKit.SummaryKeyValueRow(label: dueLabel, value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                SummaryKit.SummaryKeyValueRow(label: "Client", value: invoice.client?.name.isEmpty == false ? (invoice.client?.name ?? "") : "No Client")
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    primaryActionButton(title: "Send", systemImage: "paperplane") {
                        sharePDFOnly()
                    }

                    if invoice.documentType == "estimate" {
                        primaryActionButton(title: "Convert", systemImage: "arrow.triangle.2.circlepath") {
                            convertEstimateToInvoice()
                        }
                    } else {
                        primaryActionButton(title: invoice.isPaid ? "Mark Unpaid" : "Mark Paid", systemImage: "checkmark.circle") {
                            invoice.isPaid.toggle()
                            try? modelContext.save()
                        }
                    }

                    primaryActionButton(title: "Preview", systemImage: "doc.richtext") {
                        previewPDF()
                    }

                    primaryActionButton(title: "Detail", systemImage: "square.and.pencil") {
                        detailInvoice = invoice
                    }
                }
            }
            .listRowBackground(Color.clear)

            InvoiceSummaryDisclosureCard(
                title: "Line Items",
                subtitle: "Preview items and totals",
                icon: "list.bullet.rectangle",
                isExpanded: expandedSection == .items,
                onToggle: {
                    expandedSection = expandedSection == .items ? nil : .items
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if (invoice.items ?? []).isEmpty {
                        Text("No line items")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach((invoice.items ?? []).prefix(4)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Item" : item.itemDescription)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(item.lineTotal.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        InvoiceLineItemsSummaryView(invoice: invoice)
                    } label: {
                        Label("Edit Line Items", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .listRowBackground(Color.clear)

            InvoiceSummaryDisclosureCard(
                title: "Payments & Receipts",
                subtitle: "Paid status and remaining balance",
                icon: "creditcard",
                isExpanded: expandedSection == .payments,
                onToggle: {
                    expandedSection = expandedSection == .payments ? nil : .payments
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Status", value: invoice.isPaid ? "Paid" : "Unpaid")
                    SummaryKit.SummaryKeyValueRow(label: "Total", value: amountText)
                    SummaryKit.SummaryKeyValueRow(label: "Remaining", value: (invoice.isPaid ? 0 : invoice.total).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))

                    NavigationLink {
                        InvoicePaymentsSummaryView(invoice: invoice)
                    } label: {
                        Label("Update Payment", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .listRowBackground(Color.clear)

            InvoiceSummaryDisclosureCard(
                title: "Attachments",
                subtitle: "\(attachmentCount) file\(attachmentCount == 1 ? "" : "s")",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: {
                    expandedSection = expandedSection == .attachments ? nil : .attachments
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if attachmentCount == 0 {
                        Text("No attachments")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        InvoiceAttachmentsSummaryView(invoice: invoice)
                    } label: {
                        Label("Manage Attachments", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .listRowBackground(Color.clear)

            InvoiceSummaryDisclosureCard(
                title: "Activity / Timeline",
                subtitle: "Recent invoice events",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .activity,
                onToggle: {
                    expandedSection = expandedSection == .activity ? nil : .activity
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Created", value: invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                    SummaryKit.SummaryKeyValueRow(label: dueLabel, value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                    SummaryKit.SummaryKeyValueRow(label: "Status", value: statusText)

                    NavigationLink {
                        InvoiceActivitySummaryView(invoice: invoice)
                    } label: {
                        Label("View Full Activity", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .listRowBackground(Color.clear)

            InvoiceSummaryDisclosureCard(
                title: "Advanced",
                subtitle: "Rare actions and diagnostics",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: {
                    expandedSection = expandedSection == .advanced ? nil : .advanced
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Document ID", value: invoice.id.uuidString)

                    NavigationLink {
                        InvoiceDetailView(invoice: invoice)
                    } label: {
                        Label("Open Detail View", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle(invoice.documentType == "estimate" ? "Estimate" : "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }
        .sheet(isPresented: Binding(
            get: { previewPDFURL != nil },
            set: { if !$0 { previewPDFURL = nil } }
        )) {
            if let url = previewPDFURL {
                NavigationStack {
                    PDFPreviewView(url: url)
                        .navigationTitle(invoice.documentType == "estimate" ? "Estimate PDF" : "Invoice PDF")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Share") { shareItems = [url] }
                            }
                        }
                }
            }
        }
        .navigationDestination(item: $convertedInvoice) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
        .navigationDestination(item: $detailInvoice) { invoice in
            InvoiceDetailView(invoice: invoice)
        }
        .alert("Invoice", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func primaryActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            primaryActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .tint(SBWTheme.brandBlue)
    }

    private func primaryActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(title)
                .lineLimit(1)
                .font(.footnote.weight(.semibold))
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(.horizontal, 2)
    }

    private func sharePDFOnly() {
        do {
            let url = try DocumentFileIndexService.persistInvoicePDF(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            shareItems = [url]
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func previewPDF() {
        do {
            let url = try DocumentFileIndexService.persistInvoicePDF(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            previewPDFURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func convertEstimateToInvoice() {
        guard invoice.documentType == "estimate" else { return }
        do {
            let created = try EstimateToInvoiceConverter.convert(
                estimate: invoice,
                profiles: profiles,
                context: modelContext
            )
            if created.id != invoice.id {
                convertedInvoice = created
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct InvoiceLineItemsSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice
    @State private var selectedLineItem: LineItem?

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Line Items")

                if (invoice.items ?? []).isEmpty {
                    Text("No line items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(invoice.items ?? []) { item in
                        Button {
                            selectedLineItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Item" : item.itemDescription)
                                        .lineLimit(1)
                                    Text("\(item.quantity.formatted()) x \(item.unitPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    let newItem = LineItem(itemDescription: "", quantity: 1, unitPrice: 0)
                    if invoice.items == nil { invoice.items = [] }
                    invoice.items?.append(newItem)
                    newItem.invoice = invoice
                    try? modelContext.save()
                    selectedLineItem = newItem
                } label: {
                    Label("Add Line Item", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Line Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .navigationDestination(item: $selectedLineItem) { item in
            LineItemEditView(item: item)
        }
    }
}

private struct InvoicePaymentsSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Payments")
                SummaryKit.SummaryKeyValueRow(label: "Status", value: invoice.isPaid ? "Paid" : "Unpaid")
                SummaryKit.SummaryKeyValueRow(
                    label: "Total",
                    value: invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                Button {
                    invoice.isPaid.toggle()
                    try? modelContext.save()
                } label: {
                    Text(invoice.isPaid ? "Mark Unpaid" : "Mark Paid")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct InvoiceAttachmentsSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice

    var body: some View {
        AttachmentsManagerView(invoice: invoice)
            .navigationTitle("Invoice Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

private struct InvoiceActivitySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Activity / Timeline")
                SummaryKit.SummaryKeyValueRow(
                    label: "Created",
                    value: invoice.issueDate.formatted(date: .abbreviated, time: .omitted)
                )
                SummaryKit.SummaryKeyValueRow(
                    label: invoice.documentType == "estimate" ? "Valid Until" : "Due Date",
                    value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
                )
                SummaryKit.SummaryKeyValueRow(
                    label: invoice.isPaid ? "Paid" : "Unpaid",
                    value: invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Portal Synced",
                    value: (invoice.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "No upload errors" : "Upload error"
                )
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct BookingOverviewView: View {
    let request: BookingRequestItem
    let onStatusChange: (String) -> Void

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
    }

    var body: some View {
        BookingDetailView(request: request, onStatusChange: onStatusChange)
    }
}

struct ContractBodyView: View {
    @Bindable var contract: Contract

    var body: some View {
        ContractDetailView(contract: contract)
    }
}

struct ContractActivityView: View {
    @Bindable var contract: Contract

    var body: some View {
        ContractDetailView(contract: contract)
    }
}

private struct ClientContractSelection: Identifiable, Hashable {
    let id: UUID
}

struct ClientContractsView: View {
    let businessID: UUID
    let clientID: UUID
    let clientName: String
    @Query private var contracts: [Contract]
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

    private var filteredContracts: [Contract] {
        contracts.filter { contract in
            contract.client?.id == clientID ||
            contract.invoice?.client?.id == clientID ||
            contract.estimate?.client?.id == clientID ||
            contract.job?.clientID == clientID
        }
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : clientName,
                    subtitle: "Contracts",
                    status: filteredContracts.isEmpty ? "EMPTY" : "\(filteredContracts.count) TOTAL"
                )
            }
            .listRowBackground(Color.clear)

            if filteredContracts.isEmpty {
                Text("No contracts found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredContracts) { contract in
                    Button {
                        selectedContract = ClientContractSelection(id: contract.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contract.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contract" : contract.title)
                                .font(.headline)
                            Text(contract.statusRaw.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Contracts")
        .navigationDestination(item: $selectedContract) { selection in
            ClientContractRouteView(contractID: selection.id)
        }
    }
}

private struct ClientContractRouteView: View {
    @Environment(\.modelContext) private var modelContext

    let contractID: UUID

    @State private var contract: Contract?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let contract {
                ContractSummaryView(contract: contract)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Load Contract",
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
            do {
                let descriptor = FetchDescriptor<Contract>(
                    predicate: #Predicate<Contract> { contract in
                        contract.id == contractID
                    }
                )
                contract = try modelContext.fetch(descriptor).first
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
