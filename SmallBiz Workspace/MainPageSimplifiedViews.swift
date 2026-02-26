import SwiftUI
import SwiftData
import MessageUI

struct SBWCardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SBWStatusPill: View {
    let text: String

    var body: some View {
        let chip = SBWTheme.chip(forStatus: text)
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(chip.bg))
            .foregroundStyle(chip.fg)
    }
}

struct SBWSectionHeaderRow: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SBWPrimaryActionRow: View {
    struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.role = role
            self.action = action
        }
    }

    let actions: [ActionItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { item in
                Button(role: item.role, action: item.action) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                        Text(item.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .font(.subheadline.weight(.semibold))
                    .sbwPrimaryActionButtonLayout()
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
        }
    }
}

private struct SBWPrimaryActionButtonLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .padding(.horizontal, 4)
    }
}

private extension View {
    func sbwPrimaryActionButtonLayout() -> some View {
        modifier(SBWPrimaryActionButtonLayoutModifier())
    }
}

private enum InvoiceSummarySection: Hashable {
    case lineItems
    case payments
    case attachments
    case activity
    case advanced
}

private enum InvoiceSummarySheet: String, Identifiable {
    case lineItems
    case payments
    case attachments
    case activity
    case advanced

    var id: String { rawValue }
}

struct InvoiceOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var invoice: Invoice
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]
    @Query private var allAttachments: [InvoiceAttachment]

    @State private var expandedSection: InvoiceSummarySection? = nil
    @State private var activeSheet: InvoiceSummarySheet? = nil
    @State private var shareItems: [Any]? = nil
    @State private var showingMail = false
    @State private var mailAttachment: Data? = nil
    @State private var mailFilename: String = ""
    @State private var exportError: String? = nil
    @State private var portalError: String? = nil
    @State private var portalNotice: String? = nil

    private var titleText: String {
        invoice.documentType == "estimate" ? "Estimate" : "Invoice"
    }

    private var statusText: String {
        if invoice.documentType == "estimate" {
            let raw = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "DRAFT" : raw.uppercased()
        }
        return invoice.isPaid ? "PAID" : "UNPAID"
    }

    private var invoiceAttachments: [InvoiceAttachment] {
        allAttachments.filter { $0.invoiceKey == invoice.id.uuidString }
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: "\(titleText) \(invoice.invoiceNumber)",
                    subtitle: "Summary",
                    status: statusText
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Amount",
                    value: invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Due",
                    value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Client",
                    value: invoice.client?.name ?? "No Client"
                )
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                SummaryKit.PrimaryActionRow(actions: [
                    .init(title: invoice.documentType == "estimate" ? "Send" : "Send", systemImage: "paperplane") {
                        sendPrimaryAction()
                    },
                    .init(title: invoice.documentType == "estimate" ? "Convert" : (invoice.isPaid ? "Mark Unpaid" : "Mark Paid"), systemImage: invoice.documentType == "estimate" ? "arrow.triangle.2.circlepath" : "checkmark.circle") {
                        if invoice.documentType == "estimate" {
                            invoice.documentType = "invoice"
                        } else {
                            invoice.isPaid.toggle()
                        }
                        try? modelContext.save()
                    },
                    .init(title: "Share Portal", systemImage: "rectangle.portrait.and.arrow.right") {
                        sharePortalPrimaryAction()
                    }
                ])
                if let portalNotice {
                    Text(portalNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Line Items",
                subtitle: "Preview items and totals",
                icon: "list.bullet.rectangle",
                isExpanded: expandedSection == .lineItems,
                onToggle: { toggleSection(.lineItems) }
            ) {
                lineItemsInlineContent
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Payments & Receipts",
                subtitle: "Paid status and remaining balance",
                icon: "creditcard",
                isExpanded: expandedSection == .payments,
                onToggle: { toggleSection(.payments) }
            ) {
                paymentsInlineContent
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Attachments",
                subtitle: "Recent files",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: { toggleSection(.attachments) }
            ) {
                attachmentsInlineContent
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Activity / Timeline",
                subtitle: "Recent invoice events",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .activity,
                onToggle: { toggleSection(.activity) }
            ) {
                activityInlineContent
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Advanced",
                subtitle: "Rare actions and diagnostics",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: { toggleSection(.advanced) }
            ) {
                advancedInlineContent
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("\(titleText) Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMail) { mailSheet }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                Group {
                    switch sheet {
                    case .lineItems:
                        InvoiceLineItemsView(invoice: invoice, showsDoneButton: true)
                    case .payments:
                        InvoicePaymentsView(invoice: invoice, showsDoneButton: true)
                    case .attachments:
                        InvoiceAttachmentsView(invoice: invoice, showsDoneButton: true)
                    case .activity:
                        InvoiceActivityView(invoice: invoice, showsDoneButton: true)
                    case .advanced:
                        InvoiceDetailView(invoice: invoice)
                    }
                }
            }
        }
        .alert("Send Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Portal", isPresented: Binding(
            get: { portalError != nil },
            set: { if !$0 { portalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(portalError ?? "")
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }

    private func toggleSection(_ section: InvoiceSummarySection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
    }

    private var lineItemsInlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let items = invoice.items, !items.isEmpty {
                ForEach(Array(items.prefix(3))) { item in
                    HStack {
                        Text(item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Item" : item.itemDescription)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.quantity.formatted(.number)) • \(item.lineTotal.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if items.count > 3 {
                    Text("+\(items.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No line items yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.35)
            HStack {
                Text("Subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(invoice.subtotal.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
            }
            HStack {
                Text("Tax")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(invoice.taxAmount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
            }
            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text(invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                    .fontWeight(.semibold)
            }

            HStack(spacing: 10) {
                Button("View All") { activeSheet = .lineItems }
                    .buttonStyle(.bordered)
                Button("Add Line Item") { activeSheet = .lineItems }
                    .buttonStyle(.borderedProminent)
                    .tint(SBWTheme.brandBlue)
            }
        }
    }

    private var paymentsInlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let paidAmount = invoice.totalCents - invoice.remainingDueCents
            summaryRow("Status", invoice.isPaid ? "Paid" : "Unpaid")
            summaryRow("Amount Paid", currency(fromCents: max(paidAmount, 0)))
            summaryRow("Remaining", currency(fromCents: invoice.isPaid ? 0 : invoice.remainingDueCents))
            if let ms = invoice.sourceBookingDepositPaidAtMs {
                let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
                summaryRow("Last Receipt", date.formatted(date: .abbreviated, time: .omitted))
            } else {
                summaryRow("Last Receipt", "Not available")
            }
            Button("View Payments") { activeSheet = .payments }
                .buttonStyle(.bordered)
        }
    }

    private var attachmentsInlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Files", "\(invoiceAttachments.count)")
            if invoiceAttachments.isEmpty {
                Text("No attachments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(invoiceAttachments.prefix(3))) { attachment in
                    Text(attachment.file?.displayName ?? "File")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            Button("Manage Attachments") { activeSheet = .attachments }
                .buttonStyle(.bordered)
        }
    }

    private var activityInlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(recentActivityEntries.prefix(5).enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(SBWTheme.brandBlue.opacity(0.7))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("View Full Activity") { activeSheet = .activity }
                .buttonStyle(.bordered)
        }
    }

    private var advancedInlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Invoice ID", invoice.id.uuidString)
            summaryRow("Portal Upload", invoice.portalNeedsUpload ? "Pending" : "Synced")
            if let uploadedMs = invoice.portalLastUploadedAtMs {
                let date = Date(timeIntervalSince1970: TimeInterval(uploadedMs) / 1000.0)
                summaryRow("Last Upload", date.formatted(date: .abbreviated, time: .shortened))
            }
            Button("Open Advanced Editor") { activeSheet = .advanced }
                .buttonStyle(.bordered)
            Button("Delete Invoice", role: .destructive) {
                modelContext.delete(invoice)
                try? modelContext.save()
            }
            .buttonStyle(.bordered)
        }
    }

    private var recentActivityEntries: [(title: String, detail: String)] {
        var entries: [(String, String)] = []
        entries.append(("Created", invoice.issueDate.formatted(date: .abbreviated, time: .omitted)))
        entries.append(("Due Date", invoice.dueDate.formatted(date: .abbreviated, time: .omitted)))
        entries.append((invoice.isPaid ? "Marked Paid" : "Unpaid", invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))))
        entries.append((invoice.portalNeedsUpload ? "Portal Upload Pending" : "Portal Synced", invoice.portalLastUploadError ?? "No upload errors"))
        if invoice.documentType == "estimate" {
            entries.append(("Estimate Status", invoice.estimateStatus.capitalized))
        }
        return entries
    }

    private func currency(fromCents cents: Int) -> String {
        (Double(cents) / 100.0).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    private var mailSheet: some View {
        Group {
            if let data = mailAttachment, MFMailComposeViewController.canSendMail() {
                MailComposerView(
                    subject: "\(invoice.documentType == "estimate" ? "Estimate" : "Invoice") \(invoice.invoiceNumber)",
                    body: "Hi,\n\nAttached is \(invoice.documentType == "estimate" ? "estimate" : "invoice") \(invoice.invoiceNumber).\n\nThank you.",
                    attachmentData: data,
                    attachmentMimeType: "application/pdf",
                    attachmentFileName: mailFilename.isEmpty ? "\(invoice.invoiceNumber).pdf" : mailFilename
                )
            } else {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Mail Not Available",
                        systemImage: "envelope.badge",
                        description: Text("Set up Apple Mail on your device, or use Share instead.")
                    )
                    Button("Close") { showingMail = false }
                }
                .padding()
            }
        }
    }

    private func sendPrimaryAction() {
        do {
            let pdfData = InvoicePDFService.makePDFData(
                invoice: invoice,
                profiles: profiles,
                context: modelContext,
                businesses: businesses
            )
            mailAttachment = pdfData
            mailFilename = "\(invoice.invoiceNumber).pdf"

            if invoice.documentType == "estimate" {
                let normalized = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "draft" {
                    invoice.estimateStatus = "sent"
                    try? modelContext.save()
                }
            }

            if MFMailComposeViewController.canSendMail() {
                showingMail = true
            } else {
                let url = try writeInvoicePDFTempURL(suffix: "send")
                shareItems = [url]
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func sharePortalPrimaryAction() {
        Task {
            do {
                let url = try await buildPortalLink(mode: nil)
                shareItems = [url]
                showPortalNotice("Sharing portal link…")
            } catch {
                portalError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func buildPortalLink(mode: String? = nil) async throws -> URL {
        if invoice.client?.portalEnabled == false {
            throw NSError(
                domain: "Portal",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Client portal is disabled for this client."]
            )
        }

        let amountCents = Int((invoice.total * 100).rounded())
        guard amountCents > 0 else {
            throw NSError(
                domain: "Portal",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey:
                    "This invoice total is $0.00. Add line items / amount before requesting payment."
                ]
            )
        }

        let businessName = resolvedPortalBusinessName()
        let token = try await PortalBackend.shared.createInvoicePortalToken(
            invoice: invoice,
            business: businesses.first(where: { $0.id == invoice.businessID }),
            businessName: businessName
        )

        let modeValue = (mode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? mode!
            : "live"

        if invoice.documentType == "estimate" {
            return PortalBackend.shared.portalEstimateURL(
                estimateId: invoice.id.uuidString,
                token: token,
                mode: modeValue
            )
        }
        return PortalBackend.shared.portalInvoiceURL(
            invoiceId: invoice.id.uuidString,
            token: token,
            mode: modeValue
        )
    }

    private func resolvedPortalBusinessName() -> String? {
        let snapshotName = invoice.businessSnapshot?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !snapshotName.isEmpty { return snapshotName }
        if let profile = profiles.first(where: { $0.businessID == invoice.businessID }) {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    private func writeInvoicePDFTempURL(suffix: String) throws -> URL {
        let pdfData = InvoicePDFService.makePDFData(
            invoice: invoice,
            profiles: profiles,
            context: modelContext,
            businesses: businesses
        )
        let base = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBase = base.isEmpty ? "Invoice" : base.replacingOccurrences(of: " ", with: "-")
        let filename = "\(safeBase)-\(suffix).pdf"
        return try InvoicePDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
    }

    @MainActor
    private func showPortalNotice(_ text: String) {
        portalNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if portalNotice == text { portalNotice = nil }
        }
    }
}

struct InvoiceLineItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice
    var showsDoneButton: Bool = false
    @State private var selectedLineItem: LineItem? = nil

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Line Items")
                if let items = invoice.items, !items.isEmpty {
                    ForEach(items) { item in
                        let title = item.itemDescription.isEmpty ? "Item" : item.itemDescription
                        let detail = "\(item.quantity.formatted(.number)) x \(item.unitPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))"
                        Button {
                            selectedLineItem = item
                        } label: {
                            SBWNavigationRow(title: title, subtitle: detail)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteItems)
                } else {
                    Text("No line items")
                        .foregroundStyle(.secondary)
                }
                Button {
                    let newItem = LineItem(itemDescription: "", quantity: 1, unitPrice: 0)
                    newItem.invoice = invoice
                    var updated = invoice.items ?? []
                    updated.append(newItem)
                    invoice.items = updated
                    try? modelContext.save()
                } label: {
                    Label("Add Line Item", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Line Items")
        .navigationDestination(item: $selectedLineItem) { item in
            LineItemEditView(item: item)
        }
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        guard var items = invoice.items else { return }
        for index in offsets where index < items.count {
            modelContext.delete(items[index])
            items.remove(at: index)
        }
        invoice.items = items
        try? modelContext.save()
    }
}

struct InvoicePaymentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice
    var showsDoneButton: Bool = false

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Payments")
                summaryRow("Status", invoice.isPaid ? "Paid" : "Unpaid")
                summaryRow("Total", invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                Button(invoice.isPaid ? "Mark Unpaid" : "Mark Paid") {
                    invoice.isPaid.toggle()
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
            .listRowBackground(Color.clear)

        }
        .listStyle(.plain)
        .navigationTitle("Payments")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct InvoiceAttachmentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allAttachments: [InvoiceAttachment]
    @Bindable var invoice: Invoice
    var showsDoneButton: Bool = false

    private var attachments: [InvoiceAttachment] {
        allAttachments.filter { $0.invoiceKey == invoice.id.uuidString }
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Attachments")
                if attachments.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { attachment in
                        Text(attachment.file?.displayName ?? "File")
                    }
                }
                Text("For full attachment import/management, use Advanced editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Attachments")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct InvoiceActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice
    var showsDoneButton: Bool = false

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Activity")
                activityRow("Issue Date", invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                activityRow("Due Date", invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                activityRow("Portal Upload", invoice.portalNeedsUpload ? "Pending" : "Up to date")
                if invoice.documentType == "estimate" {
                    activityRow("Estimate Status", invoice.estimateStatus.capitalized)
                }
                if let bookingID = invoice.sourceBookingRequestId,
                   !bookingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activityRow("Booking Request", bookingID)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Activity")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func activityRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ContractOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var contract: Contract
    @State private var openAdvanced = false

    private var statusText: String {
        contract.statusRaw.uppercased()
    }

    private var clientText: String {
        if let name = contract.resolvedClient?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "No Client"
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Overview")
                HStack {
                    Text(contract.title.isEmpty ? "Contract" : contract.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    SBWStatusPill(text: statusText)
                }
                summaryRow("Client", clientText)
                summaryRow("Sent", contract.createdAt.formatted(date: .abbreviated, time: .omitted))
                summaryRow("Signed", contract.signedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Not signed")
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Primary Actions")
                SBWPrimaryActionRow(actions: [
                    .init(title: "Send", systemImage: "paperplane") {
                        if contract.status == .draft {
                            contract.status = .sent
                            try? modelContext.save()
                        }
                        openAdvanced = true
                    },
                    .init(title: "View PDF", systemImage: "doc.richtext") {
                        openAdvanced = true
                    },
                    .init(title: "Open Portal", systemImage: "rectangle.portrait.and.arrow.right") {
                        openAdvanced = true
                    }
                ])
                NavigationLink("Open Full Contract Workspace") {
                    ContractDetailView(contract: contract)
                }
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Details")
                NavigationLink("Contract Body") { ContractBodyView(contract: contract) }
                NavigationLink("Activity") { ContractActivityView(contract: contract) }
                NavigationLink("Advanced") { ContractDetailView(contract: contract) }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Contract Summary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openAdvanced) {
            ContractDetailView(contract: contract)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }
}

struct ContractBodyView: View {
    @Bindable var contract: Contract

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Contract Body", subtitle: "Readable format")
                Text(contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No body yet." : contract.renderedBody)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Contract Body")
    }
}

struct ContractActivityView: View {
    @Bindable var contract: Contract

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Activity")
                row("Created", contract.createdAt.formatted(date: .abbreviated, time: .omitted))
                row("Updated", contract.updatedAt.formatted(date: .abbreviated, time: .omitted))
                row("Status", contract.statusRaw.capitalized)
                row("Signed", contract.signedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Not signed")
                if !contract.signedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    row("Signed By", contract.signedByName)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Activity")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ClientOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var client: Client

    @State private var newInvoice: Invoice? = nil
    @State private var showContractBuilder = false
    @State private var showNewBooking = false

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Overview")
                Text(client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : client.name)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    if !client.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(client.phone, systemImage: "phone")
                            .font(.caption)
                    }
                    if !client.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(client.email, systemImage: "envelope")
                            .font(.caption)
                    }
                }
                SBWStatusPill(text: client.portalEnabled ? "ACTIVE" : "DRAFT")
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Primary Actions")
                SBWPrimaryActionRow(actions: [
                    .init(title: "Create Invoice", systemImage: "doc.badge.plus") { createInvoiceForClient() },
                    .init(title: "Create Contract", systemImage: "doc.append") { showContractBuilder = true },
                    .init(title: "Create Booking", systemImage: "calendar.badge.plus") { showNewBooking = true }
                ])
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Details")
                NavigationLink("Contact Info") { ClientEditView(client: client) }
                NavigationLink("Documents / Files") { ClientDocumentsView(client: client) }
                NavigationLink("Invoices") { ClientInvoicesView(client: client) }
                NavigationLink("Contracts") { ClientContractsView(client: client) }
                NavigationLink("Notes / Activity") { ClientActivityView(client: client) }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Client Summary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newInvoice) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
        .sheet(isPresented: $showContractBuilder) {
            NavigationStack {
                CreateContractStartView()
            }
        }
        .sheet(isPresented: $showNewBooking) {
            NavigationStack {
                NewBookingView()
            }
        }
    }

    private func createInvoiceForClient() {
        let number = "INV-\(Int(Date().timeIntervalSince1970))"
        let invoice = Invoice(invoiceNumber: number, client: client)
        invoice.businessID = client.businessID
        modelContext.insert(invoice)
        try? modelContext.save()
        newInvoice = invoice
    }
}

struct ClientDocumentsView: View {
    @Bindable var client: Client

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Documents / Files")
                NavigationLink("Manage Files") {
                    ClientEditView(client: client)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Documents")
    }
}

struct ClientInvoicesView: View {
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Bindable var client: Client

    private var filtered: [Invoice] {
        invoices.filter { invoice in
            invoice.client?.id == client.id
        }
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Invoices")
                if filtered.isEmpty {
                    Text("No invoices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { invoice in
                        NavigationLink {
                            InvoiceOverviewView(invoice: invoice)
                        } label: {
                            SBWNavigationRow(
                                title: invoice.invoiceNumber,
                                subtitle: invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                            )
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Invoices")
    }
}

struct ClientContractsView: View {
    @Query(sort: \Contract.updatedAt, order: .reverse) private var contracts: [Contract]
    @Bindable var client: Client

    private var filtered: [Contract] {
        contracts.filter { contract in
            contract.resolvedClient?.id == client.id
        }
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Contracts")
                if filtered.isEmpty {
                    Text("No contracts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { contract in
                        NavigationLink {
                            ContractSummaryView(contract: contract)
                        } label: {
                            SBWNavigationRow(
                                title: contract.title.isEmpty ? "Contract" : contract.title,
                                subtitle: contract.statusRaw.capitalized
                            )
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Contracts")
    }
}

struct ClientActivityView: View {
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Bindable var client: Client

    private var clientJobs: [Job] {
        jobs.filter { $0.clientID == client.id }
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Activity")
                if clientJobs.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(clientJobs.prefix(20)) { job in
                        let status = job.stageRaw.replacingOccurrences(of: "_", with: " ").capitalized
                        SBWNavigationRow(
                            title: job.title.isEmpty ? "Job" : job.title,
                            subtitle: "\(status) • \(job.startDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Activity")
    }
}

struct JobOverviewView: View {
    @Bindable var job: Job

    private var stageText: String {
        switch job.stage {
        case .booked: return "SCHEDULED"
        case .inProgress: return "IN PROGRESS"
        case .completed: return "DONE"
        case .canceled: return "CANCELED"
        }
    }

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Overview")
                HStack {
                    Text(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Request" : job.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    SBWStatusPill(text: stageText)
                }
                detail("Start", job.startDate.formatted(date: .abbreviated, time: .omitted))
                detail("End", job.endDate.formatted(date: .abbreviated, time: .omitted))
                detail("Location", job.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : job.locationName)
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Primary Actions")
                SBWPrimaryActionRow(actions: [
                    .init(title: "Update Status", systemImage: "arrow.triangle.2.circlepath") {},
                    .init(title: "Message", systemImage: "message") {},
                    .init(title: "Share", systemImage: "square.and.arrow.up") {}
                ])
                NavigationLink("Open Full Job Workspace") {
                    JobDetailView(job: job)
                }
            }
            .listRowBackground(Color.clear)

            SBWCardContainer {
                SBWSectionHeaderRow(title: "Details")
                NavigationLink("Attachments") { JobDetailView(job: job) }
                NavigationLink("Checklist") { JobDetailView(job: job) }
                NavigationLink("History") { JobDetailView(job: job) }
                NavigationLink("Advanced") { JobDetailView(job: job) }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Request Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }
}

struct BookingOverviewView: View {
    @Query private var profiles: [BusinessProfile]
    let request: BookingRequestItem
    var onStatusChange: (String) -> Void = { _ in }
    @State private var expandedSection: BookingSummarySection? = nil
    @State private var activeDetailSheet: BookingDetailSheet? = nil
    @State private var showStatusSheet = false
    @State private var draftStatus: String = ""
    @State private var shareItems: [Any]? = nil
    @State private var showMessageOptions = false
    @State private var messageNotice: String? = nil

    private enum BookingSummarySection: Hashable {
        case attachments
        case checklist
        case history
        case advanced
    }

    private enum BookingDetailSheet: String, Identifiable {
        case attachments
        case checklist
        case history
        case advanced

        var id: String { rawValue }
    }

    private var statusText: String {
        let raw = request.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "REQUESTED" : raw.uppercased()
    }

    private var clientText: String {
        if let name = request.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Customer"
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientText,
                    subtitle: "Booking Summary",
                    status: statusText
                )
                infoRow("Service", request.serviceType ?? "Not set")
                infoRow("Email", request.clientEmail ?? "Not set")
                infoRow("Phone", request.clientPhone ?? "Not set")
                infoRow("Requested", requestedScheduleText)
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                SummaryKit.PrimaryActionRow(actions: [
                    .init(title: "Update Status", systemImage: "arrow.triangle.2.circlepath") {
                        draftStatus = normalizedStatusRaw(request.status)
                        showStatusSheet = true
                    },
                    .init(title: "Message", systemImage: "message") {
                        showMessageOptions = true
                    },
                    .init(title: "Share", systemImage: "square.and.arrow.up") {
                        shareBookingSummary()
                    }
                ])
                if let messageNotice {
                    Text(messageNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Attachments",
                subtitle: "Files and media",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: { toggleSection(.attachments) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open full attachment management.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("View All") { activeDetailSheet = .attachments }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Checklist",
                subtitle: "Next steps",
                icon: "checklist",
                isExpanded: expandedSection == .checklist,
                onToggle: { toggleSection(.checklist) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use booking workspace checklist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open") { activeDetailSheet = .checklist }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "History",
                subtitle: "Status and timeline",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .history,
                onToggle: { toggleSection(.history) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Created", createdAtText)
                    infoRow("Current Status", statusText)
                    Button("View All") { activeDetailSheet = .history }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Advanced",
                subtitle: "IDs and diagnostics",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: { toggleSection(.advanced) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Request ID", request.requestId)
                    infoRow("Business ID", request.businessId)
                    if let slug = request.slug, !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        infoRow("Slug", slug)
                    }
                    Button("Open Advanced") { activeDetailSheet = .advanced }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Booking Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeDetailSheet) { _ in
            NavigationStack {
                BookingDetailView(request: request, onStatusChange: onStatusChange)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { activeDetailSheet = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showStatusSheet) {
            NavigationStack {
                List {
                    Section("Status") {
                        Picker("Status", selection: $draftStatus) {
                            Text("Pending").tag("pending")
                            Text("Approved").tag("approved")
                            Text("Deposit Requested").tag("deposit_requested")
                            Text("Declined").tag("declined")
                        }
                        .pickerStyle(.inline)
                    }
                }
                .navigationTitle("Update Status")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showStatusSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onStatusChange(draftStatus)
                            showStatusSheet = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }
        .confirmationDialog("Contact", isPresented: $showMessageOptions, titleVisibility: .visible) {
            if let email = normalized(request.clientEmail) {
                Button("Open Mail") {
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Copy Email") {
                    UIPasteboard.general.string = email
                    showBookingNotice("Email copied")
                }
            }
            if let phone = normalized(request.clientPhone) {
                Button("Open Messages") {
                    let digits = phone.filter(\.isNumber)
                    if let url = URL(string: "sms:\(digits)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Copy Phone") {
                    UIPasteboard.general.string = phone
                    showBookingNotice("Phone copied")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how to contact this customer.")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private var createdAtText: String {
        guard let ms = request.createdAtMs else { return "Unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var requestedScheduleText: String {
        let start = normalized(request.requestedStart) ?? "TBD"
        let end = normalized(request.requestedEnd) ?? "TBD"
        return "\(start) - \(end)"
    }

    private func toggleSection(_ section: BookingSummarySection) {
        expandedSection = (expandedSection == section) ? nil : section
    }

    private func normalizedStatusRaw(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return "pending" }
        return key
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shareBookingSummary() {
        let summary = """
        Booking: \(clientText)
        Status: \(statusText)
        Service: \(request.serviceType ?? "Not set")
        Email: \(request.clientEmail ?? "Not set")
        Phone: \(request.clientPhone ?? "Not set")
        """
        var items: [Any] = [summary]
        if let portal = bookingPortalURL() {
            items.append(portal)
        }
        shareItems = items
    }

    private func bookingPortalURL() -> URL? {
        guard let biz = UUID(uuidString: request.businessId),
              let profile = profiles.first(where: { $0.businessID == biz }) else {
            return nil
        }
        let raw = profile.bookingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let base = URL(string: raw) else { return nil }
        guard let slug = normalized(request.slug) else { return base }
        if base.absoluteString.contains(slug) { return base }
        return URL(string: "\(base.absoluteString)/\(slug)")
    }

    private func showBookingNotice(_ text: String) {
        messageNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if messageNotice == text { messageNotice = nil }
        }
    }
}
