import Foundation
import SwiftUI
import SwiftData
import MessageUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI
import ZIPFoundation

struct InvoiceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToDashboard) private var dismissToDashboard
    @Bindable var invoice: Invoice
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    // Jobs (for picker)
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)])
    private var jobs: [Job]

    // Folders (to locate/create job workspace)
    @Query private var allFolders: [Folder]

    // Attachments query (for this invoice)
    @Query private var attachments: [InvoiceAttachment]

    // Share (supports multiple items + zip)
    @State private var shareItems: [Any]? = nil

    // PDF preview
    @State private var previewItem: IdentifiableURL? = nil
    @State private var exportError: String? = nil

    @State private var showingItemPicker = false

    // Attachment picker + errors
    @State private var showFilePicker = false
    @State private var attachError: String? = nil

    // QuickLook preview for attachments
    @State private var attachmentPreviewItem: IdentifiableURL? = nil

    // Import directly into invoice attachments
    @State private var showInvoiceAttachmentFileImporter = false
    @State private var showInvoiceAttachmentPhotosSheet = false

    // Email
    @State private var showingMail = false
    @State private var mailAttachment: Data? = nil
    @State private var mailFilename: String = ""

    // Optional sections
    @State private var includeNotes = false
    @State private var includeThankYou = false
    @State private var showTotalsBreakdown = false
    @State private var showAdvancedOptions = false
    @State private var showMarkPaidConfirm = false
    @State private var showMarkUnpaidConfirm = false
    @State private var manualReports: [ManualPaymentReportDTO] = []
    @State private var loadingManualReports = false
    @State private var resolvingManualReportId: String? = nil

    // Job picker
    @State private var showJobPicker = false
    
    @State private var portalURL: URL? = nil
    @State private var portalError: String? = nil
    @State private var portalNotice: String? = nil
    @State private var openingPortal = false
    @State private var uploadingPortalPDF = false
    @State private var portalPDFNotice: String? = nil
    @State private var navigateToClientSettings: Client? = nil
    @State private var selectedLineItem: LineItem? = nil
    @State private var selectedLinkedContract: Contract? = nil


    // Open job workspace folder in Files
    private struct WorkspaceDestination: Identifiable {
        let id = UUID()
        let business: Business
        let folder: Folder
    }
    @State private var workspaceDestination: WorkspaceDestination? = nil
    @State private var workspaceError: String? = nil

    @Query private var allFileItems: [FileItem]

    @State private var pendingInvoicePDFSave: PendingPDFSave? = nil
    @State private var showInvoicePDFConflictDialog = false
    
    @State private var createdContract: Contract? = nil
    
    @State private var showPortal = false
    @State private var showTemplatePicker = false

    @ObservedObject private var portalReturn = PortalReturnRouter.shared


    private struct PendingPDFSave {
        let pdfData: Data
        let fileName: String     // e.g., "Invoice-123.pdf"
        let folder: Folder
        let existing: FileItem?
        let shareAfterSave: [Any]?
    }

    // MARK: - Init (needed for SwiftData Query filter)
    init(invoice: Invoice) {
        self.invoice = invoice

        let key = invoice.id.uuidString
        self._attachments = Query(
            filter: #Predicate<InvoiceAttachment> { a in
                a.invoiceKey == key
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        mainView
    }

    private var mainView: AnyView {
        AnyView(
        List {
            InvoiceEssentialsSection
            LineItemsSection
            TotalsDisclosureSection
            ClientPortalSection
            StatusSection
            PaymentReportsSection
            AdvancedOptionsSection
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            InvoicePinnedHeaderSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    SBWTheme.brandGradient
                        .opacity(0.12)
                        .overlay(Color(.systemBackground).opacity(0.85))
                )
                .overlay(
                    Divider().opacity(0.35),
                    alignment: .bottom
                )
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        
        .navigationDestination(item: $createdContract) { c in
            ContractDetailView(contract: c)
        }
        .navigationDestination(item: $navigateToClientSettings) { client in
            ClientEditView(client: client)
        }
        .navigationDestination(item: $selectedLineItem) { item in
            LineItemEditView(item: item)
        }
        .navigationDestination(item: $selectedLinkedContract) { contract in
            ContractDetailView(contract: contract)
        }
        
        .sheet(isPresented: $showPortal, onDismiss: {
            Task { await refreshInvoicePortalState() }
        }) {
            if let portalURL {
                SafariView(url: portalURL) {
                    showPortal = false
                }
            } else {
                Text("Missing portal URL")
            }
        }
        .onChange(of: portalReturn.didReturnFromPortal) { _, newValue in
            guard newValue else { return }
            showPortal = false
            portalReturn.consumeReturnFlag()
            Task { await refreshInvoicePortalState() }
        }
        .task {
            await ensureSnapshotForFinalizedInvoiceIfNeeded()
            await indexInvoiceIfPossible()
            EstimateDecisionSync.applyCachedDecisionIfAny(for: invoice, in: modelContext)
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            await refreshEstimateStatusFromPortal(estimate: invoice)
            await refreshManualReports()
        }
        .onChange(of: invoice.estimateStatus) { _, _ in
            let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if status == "accepted" {
                if invoice.estimateAcceptedAt == nil { invoice.estimateAcceptedAt = .now }
                invoice.estimateDeclinedAt = nil
            } else if status == "declined" {
                if invoice.estimateDeclinedAt == nil { invoice.estimateDeclinedAt = .now }
                invoice.estimateAcceptedAt = nil
            }
            try? modelContext.save()
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            Task { await indexInvoiceIfPossible() }
        }
        .onChange(of: invoice.invoiceNumber) { _, _ in
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            Task { await indexInvoiceIfPossible() }
        }
        .onChange(of: invoice.documentType) { _, _ in
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            Task { await indexInvoiceIfPossible() }
        }
        

        // ✅ Open Job Workspace Folder directly
        .sheet(item: $workspaceDestination) { dest in
            NavigationStack {
                FolderBrowserView(business: dest.business, folder: dest.folder)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        // Job picker sheet
        .sheet(isPresented: $showJobPicker) {
            NavigationStack {
                JobPickerView(
                    jobs: jobs,
                    selected: Binding(
                        get: { invoice.job },
                        set: { newValue in
                            invoice.job = newValue
                            try? modelContext.save()
                        }
                    )
                )
                .navigationTitle("Select Job")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showJobPicker = false }
                    }
                }
            }
        }

        // Sheets
        .sheet(isPresented: $showingItemPicker) { itemPickerSheet }
        .sheet(isPresented: $showTemplatePicker) {
            NavigationStack {
                InvoiceTemplatePickerSheet(
                    mode: .invoiceOverride,
                    businessDefault: resolvedBusinessDefaultTemplateKey(),
                    currentEffective: effectiveTemplateKeyForInvoice(),
                    currentSelection: InvoiceTemplateKey.from(invoice.invoiceTemplateKeyOverride),
                    onSelectTemplate: { selected in
                        invoice.invoiceTemplateKeyOverride = selected.rawValue
                        try? modelContext.save()
                    },
                    onUseBusinessDefault: {
                        invoice.invoiceTemplateKeyOverride = nil
                        try? modelContext.save()
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showTemplatePicker = false }
                    }
                }
            }
        }
        .sheet(item: $previewItem) { previewSheet(url: $0.url) }
        .sheet(isPresented: $showingMail) { mailSheet }

    
        // ShareSheet can share multiple items
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }

        // Pick existing file to attach
        .sheet(isPresented: $showFilePicker) {
            FileItemPickerView { file in
                attach(file)
            }
        }

        // QuickLook preview for attachments
        .sheet(item: $attachmentPreviewItem) { item in
            QuickLookPreview(url: item.url)
        }

        // Import from Files directly into invoice attachments
        .fileImporter(
            isPresented: $showInvoiceAttachmentFileImporter,
            allowedContentTypes: UTType.importable,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importAndAttachFromFiles(urls: urls)
            case .failure(let error):
                attachError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "A PDF with this name already exists.",
            isPresented: $showInvoicePDFConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) {
                guard let p = pendingInvoicePDFSave else { return }
                do {
                    _ = try JobExportToFilesService.savePDF(
                        data: p.pdfData,
                        preferredFileNameWithExtension: p.fileName,
                        into: p.folder,
                        existingMatch: p.existing,
                        conflictAction: .overwrite,
                        context: modelContext
                    )
                    Task { await indexInvoiceIfPossible() }
                    if let shareAfter = p.shareAfterSave { shareItems = shareAfter }
                } catch {
                    exportError = error.localizedDescription
                }
                pendingInvoicePDFSave = nil
            }

            Button("Save Copy") {
                guard let p = pendingInvoicePDFSave else { return }
                do {
                    _ = try JobExportToFilesService.savePDF(
                        data: p.pdfData,
                        preferredFileNameWithExtension: p.fileName,
                        into: p.folder,
                        existingMatch: p.existing,
                        conflictAction: .saveCopy,
                        context: modelContext
                    )
                    Task { await indexInvoiceIfPossible() }
                    if let shareAfter = p.shareAfterSave { shareItems = shareAfter }
                } catch {
                    exportError = error.localizedDescription
                }
                pendingInvoicePDFSave = nil
            }

            Button("Cancel", role: .cancel) {
                pendingInvoicePDFSave = nil
            }
        }

        // Import from Photos directly into invoice attachments
        .sheet(isPresented: $showInvoiceAttachmentPhotosSheet) {
            NavigationStack {
                List {
                    PhotosImportButton { data, suggestedName in
                        importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                        showInvoiceAttachmentPhotosSheet = false
                    }
                }
                .navigationTitle("Import Photo")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showInvoiceAttachmentPhotosSheet = false }
                    }
                }
            }
        }

        // Export error
        .alert("Export Failed", isPresented: .constant(exportError != nil), actions: {
            Button("OK") { exportError = nil }
        }, message: {
            Text(exportError ?? "Unknown error.")
        })

        // Attachment error
        .alert("Attachment Error", isPresented: .constant(attachError != nil), actions: {
            Button("OK") { attachError = nil }
        }, message: {
            Text(attachError ?? "Unknown error.")
        })

        // Workspace error
        .alert("Workspace", isPresented: .constant(workspaceError != nil), actions: {
            Button("OK") { workspaceError = nil }
        }, message: {
            Text(workspaceError ?? "")
        })

        // ✅ Normalize defaults + set toggles correctly
        .onAppear { normalizeInvoiceDefaultsIfNeeded() }

        // ✅ Toggles control persistence so PDF matches UI state
        .onChange(of: includeNotes) { _, isOn in
            if !isOn {
                invoice.notes = ""
                try? modelContext.save()
            }
        }
        .onChange(of: includeThankYou) { _, isOn in
            if !isOn {
                invoice.thankYou = ""
                try? modelContext.save()
            }
        }
    
        )
    }


    // MARK: - Title

    private var navigationTitleText: String {
        let num = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.documentType == "estimate" {
            return num.isEmpty ? "Estimate" : "Estimate \(num)"
        } else {
            return num.isEmpty ? "Invoice" : "Invoice \(num)"
        }
    }

    // MARK: - Normalization

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // MARK: - Active Business (single source of truth)
    private func resolvedBusinessProfile() -> BusinessProfile? {
        InvoicePDFService.resolvedBusinessProfile(for: invoice, profiles: profiles)
    }

    private func resolvedPortalBusinessName() -> String? {
        let snapshotName = trimmed(invoice.businessSnapshot?.name ?? "")
        if !snapshotName.isEmpty { return snapshotName }

        let profileName = trimmed(resolvedBusinessProfile()?.name ?? "")
        return profileName.isEmpty ? nil : profileName
    }

    private var isSnapshotLockedForInvoice: Bool {
        invoice.businessSnapshotData != nil
    }

    private func normalizeInvoiceDefaultsIfNeeded() {
        let profile = resolvedBusinessProfile()
        let defaultThankYou = trimmed(profile?.defaultThankYou ?? "")
        let defaultTerms = trimmed(profile?.defaultTerms ?? "")

        // Clear legacy defaults (Net 14 + default thank-you/terms)
        if trimmed(invoice.paymentTerms).lowercased() == "net 14" {
            invoice.paymentTerms = ""
        }
        if trimmed(invoice.thankYou) == defaultThankYou {
            invoice.thankYou = ""
        }
        if trimmed(invoice.termsAndConditions) == defaultTerms {
            invoice.termsAndConditions = ""
        }
        if trimmed(invoice.notes) == "—" {
            invoice.notes = ""
        }

        includeNotes = !trimmed(invoice.notes).isEmpty
        includeThankYou = !trimmed(invoice.thankYou).isEmpty

        try? modelContext.save()
    }

    // MARK: - Sections
    
    private var InvoicePinnedHeaderSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(invoiceDisplayTitle)
                    .font(.headline)

                Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(invoice.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.title3.weight(.semibold))

                statusPill(text: invoiceStatusText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var InvoiceEssentialsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Client")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(invoice.client?.name ?? "No Client Selected")
                        .foregroundStyle(invoice.client == nil ? .secondary : .primary)

                    NavigationLink("Select / Edit Client") {
                        ClientPickerManualFetchView(selectedClient: $invoice.client)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                templateSelectionRow

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Job / Project")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(invoice.job?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (invoice.job?.title ?? "")
                             : "None")
                        .foregroundStyle(invoice.job == nil ? .secondary : .primary)
                        .lineLimit(1)
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button("Select Job") { showJobPicker = true }
                            .buttonStyle(.bordered)

                        if invoice.job != nil {
                            Button(role: .destructive) {
                                invoice.job = nil
                                try? modelContext.save()
                            } label: {
                                Text("Clear Job")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Divider()

                DatePicker("Issue Date", selection: $invoice.issueDate, displayedComponents: .date)
                DatePicker("Due Date", selection: $invoice.dueDate, displayedComponents: .date)
            }
            .sbwCardRow()
        }
    }

    private var templateSelectionRow: some View {
        Button {
            showTemplatePicker = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Template: \(effectiveTemplateKeyForInvoice().displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isTemplateOverrideActive {
                            Text("Override Active")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(templateSummaryText)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var LineItemsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Line Items")
                    .font(.headline)

                Button { showingItemPicker = true } label: {
                    Label("Add From Saved Items", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .sbwCardRow()
            .disabled(isEstimatePricingLocked)

            ForEach(invoice.items ?? []) { item in
                Button {
                    selectedLineItem = item
                } label: {
                    lineItemRow(item)
                }
                .buttonStyle(.plain)
                .sbwCardRow()
                .disabled(isEstimatePricingLocked)
            }
            .onDelete(perform: deleteItems)

            Button { addItem() } label: {
                Label("Add Line Item", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SBWTheme.brandBlue)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
            .disabled(isEstimatePricingLocked)
        }
    }

    private func lineItemRow(_ item: LineItem) -> some View {
        let title = item.itemDescription.isEmpty ? "Item" : item.itemDescription
        let qty = item.quantity.formatted(.number)
        let price = item.unitPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let total = item.lineTotal.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let subtitle = "\(qty) × \(price) • \(total)"

        return SBWNavigationRow(title: title, subtitle: subtitle)
    }

    private var TotalsDisclosureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTotalsBreakdown.toggle()
                    }
                } label: {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(invoice.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.headline)
                        Image(systemName: showTotalsBreakdown ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                if showTotalsBreakdown {
                    totalRow("Subtotal", invoice.subtotal)

                    HStack {
                        Text("Discount")
                        Spacer()
                        TextField("0.00", value: $invoice.discountAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Tax Rate")
                        Spacer()
                        TextField("0.00", value: $invoice.taxRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                    .onChange(of: invoice.taxRate) { _, newValue in
                        if newValue > 1 { invoice.taxRate = newValue / 100.0 }
                    }

                    totalRow("Tax", invoice.taxAmount)
                    Divider()
                    totalRow("Total", invoice.total, isEmphasis: true)
                }

                if showsBookingDepositSummary {
                    Divider()

                    HStack {
                        Text(invoice.sourceBookingDepositPaidAtMs != nil ? "Deposit received" : "Deposit")
                        Spacer()
                        Text(currencyString(fromCents: invoice.bookingDepositCents))
                            .font(.body.weight(.semibold))
                    }

                    if let paidAt = bookingDepositPaidDate {
                        Text("Paid \(paidAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Remaining due")
                        Spacer()
                        Text(currencyString(fromCents: invoice.remainingDueCents))
                            .font(.headline)
                    }

                    if invoice.overpaidCents > 0 {
                        HStack {
                            Text("Overpaid")
                            Spacer()
                            Text(currencyString(fromCents: invoice.overpaidCents))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sbwCardRow()
            .disabled(isEstimatePricingLocked)
        }
    }

    private var ClientPortalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if invoice.client == nil {
                    portalNoticeRow(
                        icon: "person.crop.circle.badge.xmark",
                        title: "No client selected.",
                        detail: "Assign a client to enable portal access."
                    )
                }

                if !isClientPortalEnabled {
                    portalNoticeRow(
                        icon: "nosign",
                        title: "Client portal is disabled for this client.",
                        detail: "Enable it in the client’s settings to generate a new portal link."
                    )
                }

                if isPortalExpiredForThisInvoice {
                    portalNoticeRow(
                        icon: "clock.arrow.circlepath",
                        title: "This client link has expired.",
                        detail: "Regenerate from the menu to issue a new link."
                    )
                }

                let canOpenPortal = (invoice.client != nil) && isClientPortalEnabled

                HStack(spacing: 8) {
                    Text(portalSyncStatusText)
                        .font(.caption)
                        .foregroundStyle(invoice.portalLastUploadError == nil ? Color.secondary : Color.red)
                    Spacer()
                    if shouldShowPortalRetryButton && canOpenPortal {
                        Button("Retry") {
                            triggerInvoicePortalAutoSync()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(invoice.portalUploadInFlight)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            openingPortal = true
                            portalError = nil
                            portalNotice = nil

                            do {
                                let url = try await buildPortalLink(mode: nil)
                                portalURL = url
                                showPortal = true
                            } catch {
                                portalURL = nil
                                print("Portal open failed:", error)
                                portalError = error.localizedDescription
                            }

                            openingPortal = false
                        }
                    } label: {
                        if openingPortal {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Opening secure portal…")
                            }
                        } else {
                            if invoice.isPaid {
                                Label("View Client Portal (Paid)", systemImage: "checkmark.seal")
                            } else {
                                Label("View in Client Portal", systemImage: "rectangle.and.hand.point.up.left")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SBWTheme.brandBlue)
                    .disabled(openingPortal || !canOpenPortal)
                    .opacity((openingPortal || !canOpenPortal) ? 0.6 : 1)

                    Spacer()

                    Menu {
                        Button {
                            Task {
                                openingPortal = true
                                portalError = nil
                                portalNotice = nil

                                do {
                                    let url = try await buildPortalLink(mode: nil)
                                    UIPasteboard.general.string = url.absoluteString
                                    showNotice("Client link copied")
                                } catch {
                                    print("Copy link failed:", error)
                                    portalError = error.localizedDescription
                                }

                                openingPortal = false
                            }
                        } label: {
                            Label("Copy Client Link", systemImage: "doc.on.doc")
                        }

                        Button {
                            Task {
                                openingPortal = true
                                portalError = nil
                                portalNotice = nil

                                do {
                                    let url = try await buildPortalLink(mode: nil)
                                    shareItems = [url]
                                    showNotice("Sharing link…")
                                } catch {
                                    print("Share link failed:", error)
                                    portalError = error.localizedDescription
                                }

                                openingPortal = false
                            }
                        } label: {
                            Label("Share Client Link", systemImage: "square.and.arrow.up")
                        }

                        if isPortalExpiredForThisInvoice {
                            Button {
                                Task {
                                    openingPortal = true
                                    portalError = nil
                                    portalNotice = nil

                                    do {
                                        let url = try await buildPortalLink(mode: nil)
                                        portalURL = url
                                        showPortal = true
                                        portalReturn.expiredInvoiceID = nil
                                    } catch {
                                        portalError = error.localizedDescription
                                    }

                                    openingPortal = false
                                }
                            } label: {
                                Label("Regenerate Link", systemImage: "arrow.clockwise")
                            }
                        }

                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .padding(.vertical, 6)
                    }
                    .disabled(openingPortal || !canOpenPortal)
                    .opacity((openingPortal || !canOpenPortal) ? 0.6 : 1)
                }

                if canOpenPortal {
                    Button {
                        Task {
                            openingPortal = true
                            portalError = nil
                            portalNotice = nil

                            do {
                                let url = try await buildPortalLink(mode: nil)
                                portalURL = url
                                showPortal = true
                            } catch {
                                portalURL = nil
                                portalError = error.localizedDescription
                            }

                            openingPortal = false
                        }
                    } label: {
                        Label("Open Client Payment Page", systemImage: "creditcard")
                    }
                    .buttonStyle(.bordered)
                    .disabled(openingPortal)
                    .opacity(openingPortal ? 0.6 : 1)
                }

                if let client = invoice.client, !isClientPortalEnabled {
                    Button {
                        navigateToClientSettings = client
                    } label: {
                        Label("Enable Client Portal", systemImage: "togglepower")
                    }
                    .buttonStyle(.bordered)
                    .tint(SBWTheme.brandBlue)
                }

                if PortalAutoSyncService.isEligible(invoice: invoice) {
                    if invoice.portalUploadInFlight {
                        Text("Uploading latest changes in the background…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if invoice.portalNeedsUpload {
                        Text("Pending upload—tap Done to sync latest changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let portalNotice {
                    Text(portalNotice)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let message = invoice.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if let issuerName = resolvedPortalBusinessName() {
                    Text("Issued by: \(issuerName)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let portalErrorMessage = portalError {
                    portalErrorRow(portalErrorMessage)
                }
            }
            .sbwCardRow()
        }
    }

    private var StatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    statusPill(text: invoiceStatusText)
                    Spacer()
                }

                if invoice.documentType == "estimate" {
                    if let timestamp = estimateStatusTimestampText {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "declined" {
                        Label("This estimate was declined in the portal.", systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if invoice.isPaid {
                        HStack(spacing: 8) {
                            Label("Paid", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Mark as Unpaid") { showMarkUnpaidConfirm = true }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Button("Mark as Paid") { showMarkPaidConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(SBWTheme.brandGreen)
                    }
                }
            }
            .sbwCardRow()
            .confirmationDialog(
                "Mark this invoice as paid?",
                isPresented: $showMarkPaidConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark as Paid", role: .destructive) {
                    invoice.isPaid = true
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Mark this invoice as unpaid?",
                isPresented: $showMarkUnpaidConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark as Unpaid", role: .destructive) {
                    invoice.isPaid = false
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var PaymentReportsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Payment Reports")
                        .font(.headline)
                    Spacer()
                    if loadingManualReports {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Refresh") {
                            Task { await refreshManualReports() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                let pendingForInvoice = manualReports.filter {
                    $0.invoiceId == invoice.id.uuidString && $0.status == "pending"
                }

                if pendingForInvoice.isEmpty {
                    Text("No pending manual payment reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingForInvoice) { report in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(report.method.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(currencyString(fromCents: report.amountCents))
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(Date(timeIntervalSince1970: TimeInterval(report.createdAtMs) / 1000.0), style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let reference = report.reference, !reference.isEmpty {
                                Text("Ref: \(reference)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button("Approve") {
                                    Task { await resolveManualReport(reportId: report.id, action: "approve") }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(SBWTheme.brandGreen)
                                .disabled(resolvingManualReportId == report.id)

                                Button("Reject") {
                                    Task { await resolveManualReport(reportId: report.id, action: "reject") }
                                }
                                .buttonStyle(.bordered)
                                .disabled(resolvingManualReportId == report.id)
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .sbwCardRow()
        }
    }

    private var AdvancedOptionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                advancedPaymentCard
                    .disabled(isEstimateLocked)

                advancedNotesCard
                    .disabled(isEstimateLocked)

                advancedThankYouCard
                    .disabled(isEstimateLocked)

                advancedTermsCard
                    .disabled(isEstimateLocked)

                advancedAttachmentsHeaderCard

                if attachments.isEmpty {
                    Text("No attachments yet")
                        .foregroundStyle(.secondary)
                        .sbwCardRow()
                } else {
                    ForEach(attachments) { a in
                        Button {
                            openAttachmentPreview(a)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.file?.displayName ?? "Missing file")
                                    Text(a.file?.originalFileName ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .sbwCardRow()
                        .swipeActions {
                            Button(role: .destructive) {
                                removeAttachment(a)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }

                advancedAuditCard

                advancedPortalDetailsCard

                if invoice.documentType == "estimate" {
                    advancedEstimateWorkflowCard
                    advancedContractCard
                    advancedLinkedContractsCard

                    if invoice.estimateStatus == "accepted" {
                        advancedConvertCard
                    }
                }
            } label: {
                HStack {
                    Text("Advanced Options")
                        .font(.headline)
                    Spacer()
                }
            }
            .sbwCardRow()
        }
    }

    private var invoiceDisplayTitle: String {
        let num = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = invoice.documentType == "estimate" ? "Estimate" : "Invoice"
        return num.isEmpty ? base : "\(base) \(num)"
    }

    private var invoiceStatusText: String {
        if invoice.documentType == "estimate" {
            return estimateStatusText
        }
        return invoice.isPaid ? "PAID" : "UNPAID"
    }

    private var estimateStatusText: String {
        switch invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sent": return "SENT"
        case "accepted": return "ACCEPTED"
        case "declined": return "DECLINED"
        default: return "DRAFT"
        }
    }

    private var estimateStatusTimestampText: String? {
        let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "accepted", let acceptedAt = invoice.estimateAcceptedAt {
            return "Accepted \(acceptedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if status == "declined", let declinedAt = invoice.estimateDeclinedAt {
            return "Declined \(declinedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return nil
    }

    private func statusPill(text: String) -> some View {
        let colors = SBWTheme.chip(forStatus: text)
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
            .accessibilityLabel(Text(text))
    }

    private func portalNoticeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func portalErrorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)

                Button("Retry") {
                    self.portalError = nil
                }
                .font(.caption.weight(.semibold))
            }

            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var advancedPaymentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment Terms")
                .font(.headline)

            TextField(
                "e.g. Due on receipt, Net 14",
                text: $invoice.paymentTerms
            )
        }
        .sbwCardRow()
    }

    private var advancedNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Add Notes", isOn: $includeNotes)

            if includeNotes {
                TextEditor(text: $invoice.notes)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if invoice.notes.isEmpty {
                            Text("Enter notes…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
            }
        }
        .sbwCardRow()
    }

    private var advancedThankYouCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Add Thank You", isOn: $includeThankYou)

            if includeThankYou {
                TextEditor(text: $invoice.thankYou)
                    .frame(minHeight: 70)
                    .overlay(alignment: .topLeading) {
                        if invoice.thankYou.isEmpty {
                            Text("Enter thank-you message…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
            }
        }
        .sbwCardRow()
    }

    private var advancedTermsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terms & Conditions")
                .font(.headline)

            TextEditor(text: $invoice.termsAndConditions)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if invoice.termsAndConditions.isEmpty {
                        Text("Enter terms & conditions…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
        }
        .sbwCardRow()
    }

    private var advancedAttachmentsHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.headline)

            HStack {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Attach Existing File", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)

                Spacer()

                Menu {
                    Button("Import from Files") { showInvoiceAttachmentFileImporter = true }
                    Button("Import from Photos") { showInvoiceAttachmentPhotosSheet = true }
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .sbwCardRow()
    }

    private var advancedAuditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audit / Snapshot")
                .font(.headline)

            if invoice.businessSnapshotData != nil {
                Text("Business Snapshot: Locked")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Business Snapshot: Not Locked")
                    .foregroundStyle(.secondary)
            }

            if invoice.isDraftForSnapshotRefresh {
                Button("Refresh Snapshot") {
                    Task { await refreshBusinessSnapshotIfAllowed() }
                }
                .buttonStyle(.bordered)
            }
        }
        .sbwCardRow()
    }

    private var advancedPortalDetailsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Portal Details")
                .font(.headline)

            if let portalPDFNotice {
                Text(portalPDFNotice)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if isSnapshotLockedForInvoice {
                Text("PDF matches portal copy")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Text("Client links expire after 30 days.")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
        .sbwCardRow()
    }

    private var advancedEstimateWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estimate Workflow")
                .font(.headline)

            Picker("Status", selection: $invoice.estimateStatus) {
                Text("Draft").tag("draft")
                Text("Sent").tag("sent")
                Text("Accepted").tag("accepted")
                Text("Declined").tag("declined")
            }

            if let timestamp = estimateStatusTimestampText {
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if invoice.estimateStatus == "accepted" {
                if let job = invoice.job {
                    HStack {
                        Text("Job Linked")
                        Spacer()
                        Text(job.title.isEmpty ? "Job" : job.title)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        acceptEstimateAndCreateJob()
                    } label: {
                        Label("Create Job from Accepted Estimate", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    invoice.estimateStatus = "accepted"
                    invoice.estimateAcceptedAt = Date()
                    invoice.estimateDeclinedAt = nil
                    acceptEstimateAndCreateJob()
                } label: {
                    Label("Accept & Create Job", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(invoice.client == nil)
            }

            if invoice.client == nil {
                Text("Select a customer first to create the Job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sbwCardRow()
    }

    private var advancedContractCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contract")
                .font(.headline)

            let existing = (invoice.estimateContracts ?? [])
            let first = existing.first

            if invoice.job == nil {
                Text("Link or create a Job first to generate a contract.")
                    .foregroundStyle(.secondary)

            } else if let first {
                Button {
                    createdContract = first
                } label: {
                    Label("Open Contract", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Text("A contract already exists for this estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else {
                Button {
                    createContractFromEstimate()
                } label: {
                    Label("Create Contract for this Job", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sbwCardRow()
    }

    private var advancedLinkedContractsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Contracts")
                .font(.headline)

            let contracts = (invoice.estimateContracts ?? [])

            if contracts.isEmpty {
                Text("No contracts linked to this estimate yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contracts) { c in
                    Button {
                        selectedLinkedContract = c
                    } label: {
                        SBWNavigationRow(
                            title: c.title.isEmpty ? "Contract" : c.title,
                            subtitle: statusLabel(c.status)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sbwCardRow()
    }

    private var advancedConvertCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimate")
                .font(.headline)

            if invoice.estimateStatus != "accepted" {
                Text("Accept this estimate before converting to an invoice.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    convertEstimateToInvoice()
                } label: {
                    Label("Convert to Invoice", systemImage: "arrow.right.doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sbwCardRow()
    }

    private func statusLabel(_ status: ContractStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .signed: return "Signed"
        case .cancelled: return "Cancelled"
        }
    }
    @MainActor
    private func buildPortalLink(mode: String? = nil) async throws -> URL {
        portalError = nil
        portalNotice = nil

        if isClientPortalEnabled == false {
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

        let url: URL
        if invoice.documentType == "estimate" {
            url = PortalBackend.shared.portalEstimateURL(
                estimateId: invoice.id.uuidString,
                token: token,
                mode: modeValue
            )
        } else {
            url = PortalBackend.shared.portalInvoiceURL(
                invoiceId: invoice.id.uuidString,
                token: token,
                mode: modeValue
            )
        }

        return url
    }
    

    @MainActor
    private func showNotice(_ text: String) {
        portalNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if portalNotice == text { portalNotice = nil }
        }
    }


    private func acceptEstimateAndCreateJob() {
        exportError = nil
        if invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "accepted" {
            invoice.estimateStatus = "accepted"
            if invoice.estimateAcceptedAt == nil { invoice.estimateAcceptedAt = .now }
            invoice.estimateDeclinedAt = nil
            try? modelContext.save()
        }

        do {
            try EstimateAcceptanceHandler.handleAccepted(estimate: invoice, context: modelContext)
        } catch {
            exportError = error.localizedDescription
        }
    }



    private var isClientPortalEnabled: Bool {
        invoice.client?.portalEnabled ?? true
    }

    private var isPortalExpiredForThisInvoice: Bool {
        portalReturn.expiredInvoiceID == invoice.id
    }

    // MARK: - STEP 4 helper

    private func convertEstimateToInvoice() {
        do {
            try EstimateToInvoiceConverter.convert(
                estimate: invoice,
                profiles: profiles,
                context: modelContext
            )
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            Task { await indexInvoiceIfPossible() }
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Toolbar / Sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismissToDashboard?()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Home")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {

            Button {
                handleDoneTapped()
            } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")

            // ✅ Open Job workspace folder
            Button { openJobWorkspaceFolder() } label: { Image(systemName: "folder") }

            Button { previewPDF() } label: { Image(systemName: "doc.richtext") }
            Button { showTemplatePicker = true } label: { Image(systemName: "paintpalette") }
                .accessibilityLabel("Template")

            Menu {
                Button {
                    Task { @MainActor in
                        uploadingPortalPDF = true
                        portalPDFNotice = nil
                        do {
                            let pdfData = InvoicePDFService.makePDFData(
                                invoice: invoice,
                                profiles: profiles,
                                context: modelContext,
                                businesses: businesses
                            )
                            let prefix = (invoice.documentType == "estimate") ? "Estimate" : "Invoice"
                            let safeNumber = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                            let fallbackID = String(describing: invoice.id)
                            let namePart = safeNumber.isEmpty ? String(fallbackID.suffix(8)) : safeNumber
                            let pdfFileName = "\(prefix)-\(namePart).pdf"

                            _ = try await PortalBackend.shared.uploadInvoicePDFToBlob(
                                businessId: invoice.businessID.uuidString,
                                invoiceId: String(describing: invoice.id),
                                fileName: pdfFileName,
                                pdfData: pdfData
                            )
                            portalPDFNotice = "Portal PDF uploaded"
                        } catch {
                            exportError = error.localizedDescription
                        }
                        uploadingPortalPDF = false
                    }
                } label: {
                    if uploadingPortalPDF {
                        Label("Uploading Portal PDF…", systemImage: "arrow.up.doc")
                    } else {
                        Label("Upload PDF to Client Portal", systemImage: "arrow.up.doc")
                    }
                }

                Divider()
                Button("Share PDF Only") { sharePDFOnly() }
                Button("Share PDF + Attachments") { sharePDFWithAttachments() }
                Button("Share ZIP Package (PDF + Attachments)") { shareZIPPackage() }
                Button("Share Attachments ZIP") { shareAttachmentsZIPOnly() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Button { emailPDF() } label: { Image(systemName: "envelope") }
            Button { duplicateInvoice() } label: { Image(systemName: "doc.on.doc") }
        }
    }

    private var itemPickerSheet: some View {
        NavigationStack {
            ItemPickerView { picked in
                let desc = picked.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? picked.name
                    : "\(picked.name) — \(picked.details)"

                let newItem = LineItem(
                    itemDescription: desc,
                    quantity: picked.defaultQuantity,
                    unitPrice: picked.unitPrice
                )

                if invoice.items == nil { invoice.items = [] }
                invoice.items?.append(newItem)
                newItem.invoice = invoice

                try? modelContext.save()
            }
        }
    }

    private func previewSheet(url: URL) -> some View {
        NavigationStack {
            PDFPreviewView(url: url)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Share") { shareFromPreview(url: url) }
                    }
                }
        }
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

    // MARK: - Job Workspace (Invoices -> Job -> Files)

    private func openJobWorkspaceFolder() {
        guard let job = invoice.job else {
            workspaceError = "Select a Job first (Job / Project section)."
            return
        }

        do {
            let folderKind: JobWorkspaceSubfolder = invoice.documentType == "estimate" ? .estimates : .invoices
            let invoicesFolder = try WorkspaceProvisioningService.fetchJobSubfolder(
                job: job,
                kind: folderKind,
                context: modelContext
            )

            let biz = try fetchBusiness(for: job.businessID)
            workspaceDestination = WorkspaceDestination(business: biz, folder: invoicesFolder)

        } catch {
            workspaceError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func resolvedBusiness() -> Business? {
        if let match = businesses.first(where: { $0.id == invoice.businessID }) {
            return match
        }
        return businesses.first
    }

    private func resolvedBusinessDefaultTemplateKey() -> InvoiceTemplateKey {
        guard let business = resolvedBusiness(),
              let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) else {
            return .modern_clean
        }
        return key
    }

    private func effectiveTemplateKeyForInvoice() -> InvoiceTemplateKey {
        if let override = InvoiceTemplateKey.from(invoice.invoiceTemplateKeyOverride) {
            return override
        }
        return resolvedBusinessDefaultTemplateKey()
    }

    private var isTemplateOverrideActive: Bool {
        InvoiceTemplateKey.from(invoice.invoiceTemplateKeyOverride) != nil
    }

    private var templateSummaryText: String {
        if isTemplateOverrideActive {
            return "Applies to this invoice only"
        }
        let businessDefault = resolvedBusinessDefaultTemplateKey().displayName
        return "Using business default: \(businessDefault)"
    }

    @MainActor
    private func ensureSnapshotForFinalizedInvoiceIfNeeded() async {
        guard invoice.isFinalized else { return }
        guard invoice.businessSnapshotData == nil else { return }
        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: modelContext
        )
    }

    @MainActor
    private func refreshBusinessSnapshotIfAllowed() async {
        guard invoice.isDraftForSnapshotRefresh else { return }
        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: modelContext
        )
    }

    private func totalRow(_ label: String, _ amount: Double, isEmphasis: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(isEmphasis ? .headline : .body)
        }
    }

    private var showsBookingDepositSummary: Bool {
        guard invoice.sourceBookingRequestId != nil else { return false }
        return invoice.bookingDepositCents > 0
    }

    private var bookingDepositPaidDate: Date? {
        guard let value = invoice.sourceBookingDepositPaidAtMs, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? Double(value) / 1000.0 : Double(value)
        return Date(timeIntervalSince1970: seconds)
    }

    private func currencyString(fromCents cents: Int) -> String {
        let amount = Double(max(0, cents)) / 100.0
        return amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
    
    
    
    @MainActor
    private func indexInvoiceIfPossible() async {
        try? DocumentFileIndexService.upsertInvoicePDF(invoice: invoice, context: modelContext)
    }

    private func fetchBusiness(for businessID: UUID) throws -> Business {
        if let match = try modelContext.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first {
            return match
        }
        return try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)
    }

    private func addItem() {
        let newItem = LineItem(itemDescription: "", quantity: 1, unitPrice: 0)
        if invoice.items == nil { invoice.items = [] }
        invoice.items?.append(newItem)
        newItem.invoice = invoice
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        let current = invoice.items ?? []
        for index in offsets {
            guard index < current.count else { continue }
            let item = current[index]

            if invoice.items == nil { invoice.items = [] }
            invoice.items?.removeAll(where: { $0.id == item.id })

            modelContext.delete(item)
        }
        try? modelContext.save()
    }
    
    private func createContractFromEstimate() {
        exportError = nil
        guard let job = invoice.job else { return }

        let c = Contract() // ✅ default init
        c.businessID = invoice.businessID

        // Safe fields that we *know* exist from your app:
        c.title = "Contract - \(invoice.client?.name ?? "Client")"
        c.client = invoice.client

        // ✅ Enum, not String:
        c.status = .draft

        // ✅ Required links:
        c.job = job
        c.estimate = invoice

        modelContext.insert(c)

        do {
            try modelContext.save()
            createdContract = c
        } catch {
            exportError = error.localizedDescription
        }
    }
    
    private var isEstimateLocked: Bool {
        guard invoice.documentType == "estimate" else { return false }
        return (invoice.estimateContracts ?? []).contains(where: { $0.status == .signed })
    }

    private var isEstimateAcceptedLocked: Bool {
        guard invoice.documentType == "estimate" else { return false }
        return invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "accepted"
    }

    private var isEstimatePricingLocked: Bool {
        isEstimateLocked || isEstimateAcceptedLocked
    }

    private var isConvertedFromEstimate: Bool {
        invoice.documentType == "invoice" && invoice.estimateAcceptedAt != nil
    }



    // MARK: - PDF / Email / Duplicate

    private func previewPDF() {
        do {
            let pdfURL = try makeInvoicePDFTempURL(suffix: "preview")
            previewItem = IdentifiableURL(url: pdfURL)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func emailPDF() {
        do {
            let pdfData = InvoicePDFService.makePDFData(
                invoice: invoice,
                profiles: profiles,
                context: modelContext,
                businesses: businesses
            )

            mailAttachment = pdfData
            mailFilename = "\(invoice.invoiceNumber).pdf"

            if MFMailComposeViewController.canSendMail() {
                showingMail = true
            } else {
                let pdfURL = try makeInvoicePDFTempURL(suffix: "email")
                shareItems = [pdfURL]
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func duplicateInvoice() {
        let profile: BusinessProfile = resolvedBusinessProfile() ?? {
            let created = BusinessProfile(businessID: invoice.businessID)
            modelContext.insert(created)
            return created
        }()

        let newInvoiceNumber = InvoiceNumberGenerator.generateNextNumber(profile: profile)

        let copy = Invoice(
            businessID: invoice.businessID,
            invoiceNumber: newInvoiceNumber,
            issueDate: Date(),
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
            paymentTerms: invoice.paymentTerms,
            notes: invoice.notes,
            thankYou: invoice.thankYou,
            termsAndConditions: invoice.termsAndConditions,
            taxRate: invoice.taxRate,
            discountAmount: invoice.discountAmount,
            isPaid: false,
            documentType: "invoice",
            client: invoice.client,
            job: invoice.job,
            items: []
        )

        for item in (invoice.items ?? []) {
            let newItem = LineItem(
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            )
            if copy.items == nil { copy.items = [] }
            copy.items?.append(newItem)
            newItem.invoice = copy
        }

        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func persistInvoicePDFToJobFiles() throws -> URL {
        return try DocumentFileIndexService.persistInvoicePDF(
            invoice: invoice,
            profiles: profiles,
            context: modelContext
        )
    }

    // MARK: - Share actions

    private func shareFromPreview(url: URL) {
        var items: [Any] = [url]
        items.append(contentsOf: attachmentURLsForInvoice())
        shareItems = items
    }

    private func sharePDFOnly() {
        do {
            let url = try persistInvoicePDFToJobFiles()
            shareItems = [url]
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func forceSaveNow() {
        do {
            try modelContext.save()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var portalSyncStatusText: String {
        if !PortalAutoSyncService.isEligible(invoice: invoice) {
            return "Portal: Not eligible"
        }
        if invoice.portalUploadInFlight {
            return "Portal: Uploading..."
        }
        if let message = invoice.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return "Portal: Upload failed"
        }
        if invoice.portalNeedsUpload {
            return "Portal: Pending upload"
        }
        return "Portal: Up to date"
    }

    private var shouldShowPortalRetryButton: Bool {
        if let message = invoice.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return true
        }
        return invoice.portalNeedsUpload
    }

    private func handleDoneTapped() {
        PortalAutoSyncService.markInvoiceNeedsUploadIfChanged(
            invoice: invoice,
            business: resolvedBusiness()
        )
        forceSaveNow()
        triggerInvoicePortalAutoSync()
        dismiss()
    }

    private func triggerInvoicePortalAutoSync() {
        guard PortalAutoSyncService.isEligible(invoice: invoice) else { return }
        let invoiceID = invoice.id
        Task {
            let result = await PortalAutoSyncService.uploadInvoice(
                invoiceId: invoiceID,
                context: modelContext
            )
            await MainActor.run {
                switch result {
                case .failed(let message):
                    invoice.portalLastUploadError = message
                case .uploaded, .skippedUnchanged:
                    invoice.portalLastUploadError = nil
                case .ineligible:
                    break
                }
            }
        }
    }

    private func sharePDFWithAttachments() {
        do {
            let pdfURL = try persistInvoicePDFToJobFiles()
            var items: [Any] = [pdfURL]
            items.append(contentsOf: attachmentURLsForInvoice())
            shareItems = items
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func shareZIPPackage() {
        do {
            let pdfURL = try persistInvoicePDFToJobFiles()
            let zipURL = try createZipPackage(pdfURL: pdfURL, attachmentURLs: attachmentURLsForInvoice())
            shareItems = [zipURL]
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func shareAttachmentsZIPOnly() {
        do {
            let urls = attachmentURLsForInvoice()
            let title = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let zipName = title.isEmpty
                ? "Invoice-\(invoice.id.uuidString)-Attachments"
                : "\(title)-Attachments"

            let zipURL = try AttachmentZipExporter.zipFiles(urls, zipName: zipName)
            shareItems = [zipURL]
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func attachmentURLsForInvoice() -> [URL] {
        attachments.compactMap { a in
            guard let file = a.file else { return nil }
            return try? AppFileStore.absoluteURL(forRelativePath: file.relativePath)
        }
    }

    private func makeInvoicePDFTempURL(suffix: String) throws -> URL {
        let pdfData = InvoicePDFService.makePDFData(
            invoice: invoice,
            profiles: profiles,
            context: modelContext,
            businesses: businesses
        )
        let prefix = (invoice.documentType == "estimate") ? "Estimate" : "Invoice"
        let filename = "\(prefix)-\(invoice.invoiceNumber)-\(suffix)-\(Date().timeIntervalSince1970)"
        return try InvoicePDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
    }
    
    @MainActor
    private func refreshInvoicePortalState() async {
        await refreshInvoicePaidStatusFromPortal()
        await refreshEstimateStatusFromPortal(estimate: invoice)
        await refreshManualReports()
    }

    @MainActor
    private func refreshEstimateStatusFromPortal(estimate: Invoice) async {
        guard estimate.documentType == "estimate" else { return }

        do {
            let remote = try await PortalBackend.shared.fetchEstimateStatus(
                businessId: estimate.businessID.uuidString,
                estimateId: estimate.id.uuidString
            )

            let current = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard current != remote.status else { return }

            let normalized = remote.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "accepted" || normalized == "declined" {
                let decidedAt = remote.decidedAt ?? .now
                let decidedAtMs = Int64((decidedAt.timeIntervalSince1970 * 1000.0).rounded())
                EstimateDecisionSync.upsertDecision(
                    businessId: estimate.businessID.uuidString,
                    estimateId: estimate.id.uuidString,
                    status: normalized,
                    decidedAtMs: decidedAtMs,
                    in: modelContext
                )
                EstimateDecisionSync.setEstimateDecision(
                    estimate: estimate,
                    status: normalized,
                    decidedAtMs: decidedAtMs
                )
            } else {
                estimate.estimateStatus = remote.status
            }
            try? modelContext.save()
        } catch {
            print("Estimate status refresh failed:", error.localizedDescription)
        }
    }

    @MainActor
    private func refreshInvoicePaidStatusFromPortal() async {
        do {
            let businessId = invoice.businessID.uuidString
            let invoiceId = invoice.id.uuidString

            let status = try await PortalBackend.shared.fetchPaymentStatus(
                businessId: businessId,
                invoiceId: invoiceId
            )

            if status.paid && !invoice.isPaid {
                invoice.isPaid = true
                try? modelContext.save()
            }
        } catch {
            // Optional: show a non-blocking error
            // portalError = "Couldn’t refresh payment status"
            print("Payment status refresh failed:", error)
        }
    }

    @MainActor
    private func refreshManualReports() async {
        guard !loadingManualReports else { return }
        loadingManualReports = true
        defer { loadingManualReports = false }

        do {
            let reports = try await PortalPaymentsAPI.shared.fetchManualPaymentReports(
                businessId: invoice.businessID
            )
            manualReports = reports
        } catch {
            print("Manual reports refresh failed:", error.localizedDescription)
        }
    }

    @MainActor
    private func resolveManualReport(reportId: String, action: String) async {
        guard resolvingManualReportId == nil else { return }
        resolvingManualReportId = reportId
        defer { resolvingManualReportId = nil }

        do {
            try await PortalPaymentsAPI.shared.resolveManualPaymentReport(reportId: reportId, action: action)
            await refreshInvoicePortalState()
        } catch {
            portalError = error.localizedDescription
        }
    }


    // MARK: - ZIP creation (PDF + attachments)

    private func createZipPackage(pdfURL: URL, attachmentURLs: [URL]) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("InvoicePackage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Copy PDF into package folder
        let pdfDest = tempDir.appendingPathComponent(safeFileName(pdfURL.lastPathComponent))
        try copyReplacingIfNeeded(from: pdfURL, to: pdfDest)

        // Copy attachments into package folder
        for (idx, url) in attachmentURLs.enumerated() {
            let base = safeFileName(url.lastPathComponent)
            let uniqueName = "\(idx + 1)-\(base)"
            let dest = tempDir.appendingPathComponent(uniqueName)
            try copyReplacingIfNeeded(from: url, to: dest)
        }

        let zipName = "\(invoice.invoiceNumber)-package-\(Int(Date().timeIntervalSince1970)).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        try fm.zipItem(at: tempDir, to: zipURL)

        try? fm.removeItem(at: tempDir)
        return zipURL
    }

    private func copyReplacingIfNeeded(from src: URL, to dest: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: src, to: dest)
    }

    private func safeFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Attachments helpers

    private func attach(_ file: FileItem) {
        let fileKey = file.id.uuidString
        if attachments.contains(where: { $0.fileKey == fileKey }) { return }

        let link = InvoiceAttachment(invoice: invoice, file: file)
        modelContext.insert(link)

        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func removeAttachment(_ attachment: InvoiceAttachment) {
        modelContext.delete(attachment)
        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func openAttachmentPreview(_ attachment: InvoiceAttachment) {
        guard let file = attachment.file else {
            attachError = "This attachment’s file record is missing."
            return
        }

        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                attachError = "This file is missing from local storage."
                return
            }
            attachmentPreviewItem = IdentifiableURL(url: url)
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func importAndAttachFromFiles(urls: [URL]) {
        for url in urls {
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let folder = try resolveAttachmentFolder(kind: .attachments)

                let ext = url.pathExtension.lowercased()
                let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

                let (rel, size) = try AppFileStore.importFile(
                    from: url,
                    toRelativeFolderPath: folder.relativePath
                )

                let item = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: folder.id.uuidString,
                    folder: folder
                )
                modelContext.insert(item)

                let link = InvoiceAttachment(invoice: invoice, file: item)
                modelContext.insert(link)
            } catch {
                attachError = error.localizedDescription
                return
            }
        }

        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func importAndAttachFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let folder = try resolveAttachmentFolder(kind: .photos)

            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: folder.relativePath,
                preferredFileName: suggestedFileName
            )

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"

            let file = FileItem(
                displayName: suggestedFileName.replacingOccurrences(of: ".\(ext)", with: ""),
                originalFileName: suggestedFileName,
                relativePath: rel,
                fileExtension: ext,
                uti: uti,
                byteCount: size,
                folderKey: folder.id.uuidString,
                folder: folder
            )
            modelContext.insert(file)

            let link = InvoiceAttachment(invoice: invoice, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func resolveAttachmentFolder(kind: FolderDestinationKind) throws -> Folder {
        let business = try fetchBusiness(for: invoice.businessID)
        return try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: invoice.client,
            job: invoice.job,
            kind: kind,
            context: modelContext
        )
    }
}

private struct SBWCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func sbwCardRow() -> some View {
        modifier(SBWCardRow())
    }
}

// MARK: - Job Picker (inline so nothing is “missing in scope”)

private struct JobPickerView: View {
    let jobs: [Job]
    @Binding var selected: Job?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [Job] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return jobs }
        return jobs.filter { $0.title.lowercased().contains(q) || $0.status.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Button {
                selected = nil
                dismiss()
            } label: {
                HStack {
                    Text("None")
                    Spacer()
                    if selected == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section("Jobs") {
                if filtered.isEmpty {
                    Text("No jobs found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { job in
                        Button {
                            selected = job
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                    Text(job.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == job.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs")
    }
}
