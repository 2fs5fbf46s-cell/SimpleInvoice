import Foundation
import OSLog
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
    @State private var manualReports: [ManualPaymentReportDTO] = []
    @State private var loadingManualReports = false
    @State private var resolvingManualReportId: String? = nil

    // Job picker
    @State private var showJobPicker = false
    
    @State private var portalURL: URL? = nil
    @State private var portalError: String? = nil
    @State private var portalNotice: String? = nil
    @State private var businessInfoNotice: String? = nil
    @State private var openingPortal = false
    @State private var sendingEstimate = false
    @State private var confirmSendEstimate = false
    @State private var showEstimateNotes = false
    @State private var showEstimateAttachments = false
    @State private var showEstimateActivity = false
    @State private var confirmRecordAnswer = false
    @State private var showRenameEstimate = false
    @State private var renameEstimateText = ""
    @State private var estimateJobRoute: Job? = nil

    // Invoice layout
    @State private var pricingUnlocked = false
    @State private var confirmUnlockPricing = false
    @State private var showRecordPayment = false
    @State private var invoiceSendKind: InvoiceSendService.Kind? = nil
    @State private var sendingInvoice = false
    @State private var showInvoiceDetails = false
    @State private var showInvoiceNotes = false
    @State private var showInvoiceAttachments = false
    @State private var showInvoiceActivity = false
    @State private var uploadingPortalPDF = false
    @State private var portalPDFNotice: String? = nil
    @State private var navigateToClientSettings: Client? = nil
    @State private var selectedLineItem: LineItem? = nil
    @State private var selectedLinkedContract: Contract? = nil
    @State private var invoiceOverviewRoute: Invoice? = nil
    @State private var newRecurringScheduleDraft: RecurringInvoiceSchedule? = nil
    @State private var showingNewRecurringSchedule = false


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

    // Bundled contract (drafted alongside the estimate, before the client
    // ever sees either — see ContractCreation.create). Kept separate from
    // showTemplatePicker above, which is the unrelated invoice-PDF style
    // picker.
    @Query(sort: \ContractTemplate.name) private var contractTemplates: [ContractTemplate]
    @State private var selectedContractTemplate: ContractTemplate?
    @State private var depositAmountText: String = ""

    @State private var showPortal = false
    @State private var showTemplatePicker = false

    @ObservedObject private var portalReturn = PortalReturnRouter.shared


    private struct PendingPDFSave {
        let pdfData: Data
        let fileName: String     // e.g., "Invoice_123.pdf"
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
        // Kept off mainView's chain, which is already at the edge of what
        // the type checker will take.
        mainView
            // Here, not on a List row: a sheet attached inside a row
            // didn't present.
            .sheet(isPresented: $showRecordPayment) {
                RecordPaymentSheet(invoice: invoice)
            }
            .navigationDestination(item: $estimateJobRoute) { job in
                JobSummaryView(job: job)
            }
            .alert("Rename Estimate", isPresented: $showRenameEstimate) {
                TextField("Name", text: $renameEstimateText)
                Button("Save") {
                    let trimmed = renameEstimateText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    invoice.invoiceNumber = trimmed
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var mainView: AnyView {
        AnyView(
        List {
            if invoice.documentType == "estimate" {
                // One screen for an estimate, built around its next step —
                // see the "Estimate layout" section below.
                EstimateNextStepSection
                InvoiceEssentialsSection
                LineItemsSection
                TotalsDisclosureSection
                EstimateContractSection
                EstimateMoreSections
            } else {
                // Same shape as the estimate: next step, then the money,
                // then the details. See "Invoice layout" below.
                InvoiceNextStepSection
                if hasPendingPaymentReports {
                    PaymentReportsSection
                }
                InvoicePaymentsSection
                LineItemsSection
                TotalsDisclosureSection
                InvoiceMoreSections
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            InvoicePinnedHeaderSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // Opaque: at 85% the list scrolled visibly underneath it.
                .background(
                    Color(.systemBackground)
                        .overlay(SBWTheme.brandGradient.opacity(0.06))
                )
                .overlay(
                    Divider().opacity(0.35),
                    alignment: .bottom
                )
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar { toolbarContent }
        
        .navigationDestination(item: $createdContract) { c in
            ContractDetailView(contract: c)
        }
        .navigationDestination(item: $navigateToClientSettings) { client in
            ClientEditView(client: client)
        }
        .navigationDestination(item: $selectedLineItem) { item in
            LineItemEditView(item: item, businessID: invoice.businessID)
        }
        .navigationDestination(item: $selectedLinkedContract) { contract in
            ContractDetailView(contract: contract)
        }
        .navigationDestination(item: $invoiceOverviewRoute) { routedInvoice in
            InvoiceOverviewView(invoice: routedInvoice)
        }
        .sheet(isPresented: $showingNewRecurringSchedule, onDismiss: { newRecurringScheduleDraft = nil }) {
            NavigationStack {
                if let newRecurringScheduleDraft {
                    RecurringInvoiceScheduleFormView(schedule: newRecurringScheduleDraft, isDraft: true) {
                        showingNewRecurringSchedule = false
                    } onCancel: {
                        modelContext.delete(newRecurringScheduleDraft)
                        try? modelContext.save()
                        showingNewRecurringSchedule = false
                    }
                } else {
                    ProgressView("Loading…")
                }
            }
            .presentationDetents([.large])
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
            // The Today "ready to review" card is for a server-generated
            // invoice nobody has looked at; opening it is the review.
            if invoice.isRecurringGenerated, invoice.recurringReviewedAt == nil {
                invoice.recurringReviewedAt = .now
                try? modelContext.save()
            }
        }
        .onChange(of: invoice.estimateStatus) { oldValue, newValue in
            let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if status == "accepted" {
                if invoice.estimateAcceptedAt == nil { invoice.estimateAcceptedAt = .now }
                invoice.estimateDeclinedAt = nil
            } else if status == "declined" {
                if invoice.estimateDeclinedAt == nil { invoice.estimateDeclinedAt = .now }
                invoice.estimateAcceptedAt = nil
            }
            try? modelContext.save()
            let oldStatus = oldValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let newStatus = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if oldStatus == "draft", ["sent", "accepted", "declined"].contains(newStatus) {
                _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                    invoice: invoice,
                    profiles: profiles,
                    context: modelContext,
                    reason: .sent,
                    replaceExistingUnlockedSnapshot: true
                )
            } else {
                Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            }
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
        .onChange(of: invoice.client?.id) { _, newClientID in
            invoice.clientID = newClientID
            // Record who this is addressed to now, so the invoice survives that
            // client being deleted even if it is never rendered here.
            invoice.captureClientSnapshotIfNeeded()
            try? modelContext.save()
        }
        

        // ✅ Open Job Workspace Folder directly
        .sheet(item: $workspaceDestination) { dest in
            NavigationStack {
                FolderBrowserView(business: dest.business, folder: dest.folder)
                    .navigationBarTitleDisplayMode(.inline)
                    .sbwNavigationBarBackdrop()
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
                .sbwNavigationBarBackdrop()
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
        // The header right below already names it.
        if invoice.documentType == "estimate" {
            return "Estimate"
        } else if invoice.documentType == "invoice" {
            return "Invoice"
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
        if invoice.isBusinessInfoLocked {
            let snapshotName = trimmed(invoice.businessSnapshot?.name ?? "")
            if !snapshotName.isEmpty { return snapshotName }
        }

        let profileName = trimmed(resolvedBusinessProfile()?.name ?? "")
        return profileName.isEmpty ? nil : profileName
    }

    private var isSnapshotLockedForInvoice: Bool {
        invoice.isBusinessInfoLocked
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invoiceDisplayTitle)
                        .font(.headline)

                    Text(invoice.clientForRendering?.name ?? "No client yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if invoice.documentType != "estimate" {
                        Text(invoiceDueText)
                            .font(.caption)
                            .foregroundStyle(invoiceStage == .overdue ? Color.red : Color.primary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(invoice.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.title3.weight(.semibold))

                    statusPill(text: invoiceStatusText)

                }
            }

            if invoice.documentType == "estimate" {
                estimateStatusTrack
            } else {
                invoiceStatusTrack
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

                    // The snapshot, not the relationship: a sent invoice keeps
                    // naming its client after that client record is deleted.
                    Text(invoice.clientForRendering?.name ?? "No Client Selected")
                        .foregroundStyle(invoice.clientForRendering == nil ? .secondary : .primary)

                    if invoice.client == nil, invoice.clientSnapshot?.isEmpty == false {
                        Text("This client was deleted. The invoice keeps the details it was sent with.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                DatePicker(
                    invoice.documentType == "estimate" ? "Valid Until" : "Due Date",
                    selection: $invoice.dueDate,
                    displayedComponents: .date
                )
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
            // Locked pricing hides the add buttons rather than greying them:
            // a disabled button still reads as something to tap.
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Line Items")
                        .font(.headline)
                    Spacer()
                    if isPricingLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                }

                if !isPricingLocked {
                    Button { showingItemPicker = true } label: {
                        Label("Add From Saved Items", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            }
            .sbwCardRow()

            ForEach(invoice.items ?? []) { item in
                Button {
                    selectedLineItem = item
                } label: {
                    lineItemRow(item)
                }
                .buttonStyle(.plain)
                .sbwCardRow()
                .disabled(isPricingLocked)
                .deleteDisabled(isPricingLocked)
            }
            .onDelete(perform: deleteItems)

            if !isPricingLocked {
                Button { addItem() } label: {
                    Label("Add Line Item", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .sbwProminentButton()
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }
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
            .disabled(isPricingLocked)
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
                                    .background(Color.primary.opacity(0.12))
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

    // MARK: - Invoice layout
    //
    // The invoice's own lifecycle: Draft → Sent (maybe Viewed) → Overdue /
    // Part paid → Paid. The Next step card offers what moves it forward —
    // send it, see it, remind, record a payment — then the payments and
    // balance, the line items (locked once sent), and details collapsed.
    // It replaced a summary page plus an edit page where status, portal and
    // payment controls were scattered across five cards.

    enum InvoiceStage { case draft, sent, overdue, partPaid, paid }

    private var invoiceStage: InvoiceStage {
        if invoice.isPaid || (invoice.wasSent && invoice.totalCents > 0 && invoice.balanceDueCents == 0) { return .paid }
        guard invoice.wasSent else { return .draft }
        if invoice.isOverdue { return .overdue }
        let recorded = (invoice.payments ?? []).reduce(0) { $0 + $1.amountCents }
        return recorded > 0 ? .partPaid : .sent
    }

    private var invoiceDueText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let due = calendar.startOfDay(for: invoice.dueDate)
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        let dateText = invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
        switch invoiceStage {
        case .paid:
            let paidAt = (invoice.payments ?? []).map(\.paidAt).max()
            return paidAt.map { "Paid \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Paid"
        case .overdue:
            return "Was due \(dateText) · \(-days) day\(days == -1 ? "" : "s") late"
        default:
            if days == 0 { return "Due today" }
            if days > 0 { return "Due \(dateText) · in \(days) day\(days == 1 ? "" : "s")" }
            return "Due \(dateText)"
        }
    }

    private var invoiceStatusTrack: some View {
        let stage = invoiceStage
        let reached = stage == .draft ? 1 : stage == .paid ? 3 : 2
        let middle: Color = stage == .overdue ? .red : (stage == .partPaid ? .orange : SBWTheme.brandBlue)
        let last: Color = SBWTheme.brandGreen
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < reached ? (index == 2 ? last : (index == 1 ? middle : SBWTheme.brandBlue)) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Draft")
                Spacer()
                Text(stage == .overdue ? "Overdue" : (stage == .partPaid ? "Part paid" : "Sent"))
                Spacer()
                Text("Paid")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(invoiceStatusText.capitalized)")
    }

    private var hasPendingPaymentReports: Bool {
        manualReports.contains { $0.invoiceId == invoice.id.uuidString && $0.status == "pending" }
    }

    private var invoiceClientName: String {
        let name = (invoice.clientForRendering?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "your client" : name
    }

    private var InvoiceNextStepSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next step")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(invoiceStage == .overdue ? Color.red : SBWTheme.brandBlue)

                switch invoiceStage {
                case .draft: invoiceDraftStep
                case .sent: invoiceWaitingStep
                case .overdue: invoiceOverdueStep
                case .partPaid: invoicePartPaidStep
                case .paid: invoicePaidStep
                }

                if let portalNotice {
                    Text(portalNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let portalErrorMessage = portalError {
                    portalErrorRow(portalErrorMessage)
                }
            }
            .sbwCardRow()
            .confirmationDialog(
                invoiceSendKind == .reminder ? "Send a reminder?" : (invoice.sentAt == nil ? "Send this invoice?" : "Resend this invoice?"),
                isPresented: Binding(get: { invoiceSendKind != nil }, set: { if !$0 { invoiceSendKind = nil } }),
                titleVisibility: .visible,
                presenting: invoiceSendKind
            ) { kind in
                Button(kind == .reminder ? "Send Reminder" : (invoice.sentAt == nil ? "Send Invoice" : "Resend Invoice")) {
                    sendInvoice(kind)
                }
                Button("Cancel", role: .cancel) {}
            } message: { kind in
                Text(InvoiceSendService.confirmationMessage(for: invoice, kind: kind))
            }
        }
    }

    @ViewBuilder
    private var invoiceDraftStep: some View {
        let email = (invoice.client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.client == nil {
            estimateStepTitle("Choose a client", detail: "Pick who this invoice is for in Details below.")
            Button { showInvoiceDetails = true } label: { Label("Choose Client", systemImage: "person.crop.circle") }
                .buttonStyle(.bordered)
        } else if invoice.cannotBeSentReason != nil {
            estimateStepTitle(
                "Add what you're charging for",
                detail: invoice.totalCents == 0 && !(invoice.items ?? []).isEmpty
                    ? "Your line items add up to $0.00. Set their prices, then send it."
                    : "Add a line item below, then send it."
            )
        } else if email.isEmpty {
            estimateStepTitle("Add an email for \(invoiceClientName)", detail: "The invoice is emailed with a link to pay online.")
            Button { navigateToClientSettings = invoice.client } label: { Label("Edit Client", systemImage: "person.crop.circle") }
                .buttonStyle(.bordered)
        } else if !isClientPortalEnabled {
            estimateStepTitle("Turn on the client portal", detail: "\(invoiceClientName) views and pays invoices in their client portal.")
            Button { navigateToClientSettings = invoice.client } label: { Label("Enable Client Portal", systemImage: "togglepower") }
                .buttonStyle(.bordered)
        } else {
            estimateStepTitle(
                "Send it to \(invoiceClientName)",
                detail: "Emails \(email) a link to view and pay online."
            )
            HStack(spacing: 10) {
                Button { invoiceSendKind = .send } label: { sendingLabel("Send Invoice", icon: "paperplane.fill") }
                    .sbwProminentButton()
                    .disabled(sendingInvoice)
                Button { previewPDF() } label: { Label("Preview", systemImage: "doc.richtext") }
                    .buttonStyle(.bordered)
            }
        }
        if invoice.totalCents > 0 {
            Button("Paid already? Record a payment") { showRecordPayment = true }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(SBWTheme.brandBlue)
        }
    }

    @ViewBuilder
    private var invoiceWaitingStep: some View {
        estimateStepTitle(
            "Waiting on payment",
            detail: invoice.viewedAt.map { "Viewed \($0.formatted(date: .abbreviated, time: .omitted)). You'll get a notification when it's paid." }
                ?? "You'll get a notification when it's paid."
        )
        HStack(spacing: 10) {
            Button { openClientPortal() } label: {
                if openingPortal { ProgressView() } else { Label("View in Portal", systemImage: "rectangle.and.hand.point.up.left") }
            }
            .buttonStyle(.bordered)
            .disabled(openingPortal)
            Button { showRecordPayment = true } label: { Label("Record Payment", systemImage: "banknote") }
                .buttonStyle(.bordered)
        }
        HStack(spacing: 10) {
            Button { invoiceSendKind = .send } label: { sendingLabel("Resend", icon: "paperplane") }
                .buttonStyle(.bordered)
                .disabled(sendingInvoice)
            Button { copyClientLink() } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                .buttonStyle(.bordered)
                .disabled(openingPortal)
        }
    }

    @ViewBuilder
    private var invoiceOverdueStep: some View {
        let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: invoice.dueDate), to: Calendar.current.startOfDay(for: .now)).day ?? 0, 1)
        estimateStepTitle(
            "\(currencyString(fromCents: invoice.balanceDueCents)) is \(days) day\(days == 1 ? "" : "s") overdue",
            detail: invoice.lastReminderAt.map { "Last reminder sent \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "No reminder sent yet."
        )
        HStack(spacing: 10) {
            Button { invoiceSendKind = .reminder } label: { sendingLabel("Remind Client", icon: "bell.fill") }
                .sbwProminentButton(.red)
                .disabled(sendingInvoice)
            Button { showRecordPayment = true } label: { Label("Record Payment", systemImage: "banknote") }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var invoicePartPaidStep: some View {
        let lastPayment = (invoice.payments ?? []).max { $0.paidAt < $1.paidAt }
        estimateStepTitle(
            "\(currencyString(fromCents: invoice.balanceDueCents)) still owed",
            detail: lastPayment.map { "Paid \(currencyString(fromCents: $0.amountCents)) by \($0.methodLabel.lowercased()) on \($0.paidAt.formatted(date: .abbreviated, time: .omitted))." } ?? ""
        )
        HStack(spacing: 10) {
            Button { showRecordPayment = true } label: { Label("Record Payment", systemImage: "banknote") }
                .sbwProminentButton()
            Button { invoiceSendKind = .reminder } label: { sendingLabel("Remind", icon: "bell") }
                .buttonStyle(.bordered)
                .disabled(sendingInvoice)
        }
    }

    @ViewBuilder
    private var invoicePaidStep: some View {
        let online = (invoice.payments ?? []).contains { $0.source == "portal" }
        estimateStepTitle(
            "Paid in full",
            detail: online ? "Paid through the client portal." : "Nothing left to collect."
        )
        HStack(spacing: 10) {
            Button { sharePDFOnly() } label: { Label("Share Receipt", systemImage: "doc.text") }
                .buttonStyle(.bordered)
            Button { duplicateInvoice() } label: { Label(duplicateActionTitle, systemImage: "doc.on.doc") }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func sendingLabel(_ title: String, icon: String) -> some View {
        if sendingInvoice {
            HStack(spacing: 8) { ProgressView(); Text("Sending…") }
        } else {
            Label(title, systemImage: icon)
        }
    }

    private func sendInvoice(_ kind: InvoiceSendService.Kind) {
        guard !sendingInvoice else { return }
        sendingInvoice = true
        portalError = nil
        portalNotice = nil
        forceSaveNow()
        Task {
            defer { sendingInvoice = false }
            do {
                switch try await InvoiceSendService.send(
                    invoice,
                    kind: kind,
                    context: modelContext,
                    businessName: resolvedPortalBusinessName()
                ) {
                case .emailed(let email):
                    Haptics.success()
                    pricingUnlocked = false
                    showNotice(kind == .reminder ? "Reminder sent to \(email)" : "Invoice sent to \(email)")
                case .publishedNotEmailed(let link, _):
                    if let link { UIPasteboard.general.string = link }
                    portalError = link == nil
                        ? "The invoice is in your client's portal, but the email didn't go out. Try again in a moment."
                        : "The invoice is in your client's portal, but the email didn't go out. Its link is copied — paste it to your client."
                }
            } catch {
                portalError = error.localizedDescription
            }
        }
    }

    private var InvoicePaymentsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Payments")
                        .font(.headline)
                    Spacer()
                    if invoiceStage != .paid && invoice.totalCents > 0 {
                        Button { showRecordPayment = true } label: { Label("Record", systemImage: "plus") }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                    }
                }

                let payments = (invoice.payments ?? []).sorted { $0.paidAt < $1.paidAt }
                if invoice.bookingDepositCents > 0 {
                    paymentRow(title: "Booking deposit", detail: invoice.sourceBookingDepositPaidAtMs.map {
                        Date(timeIntervalSince1970: TimeInterval($0) / 1000).formatted(date: .abbreviated, time: .omitted)
                    } ?? "", amountCents: invoice.bookingDepositCents)
                }
                if payments.isEmpty && invoice.bookingDepositCents == 0 {
                    Text(invoice.isPaid ? "Marked paid." : "No payments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(payments) { payment in
                    paymentRow(
                        title: payment.methodLabel,
                        detail: [payment.paidAt.formatted(date: .abbreviated, time: .omitted), payment.note]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        amountCents: payment.amountCents
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            InvoicePaymentService.remove(payment, from: invoice, context: modelContext)
                            Task { await InvoicePaymentService.publishIfSent(invoice, context: modelContext) }
                        } label: {
                            Label("Remove Payment", systemImage: "trash")
                        }
                    }
                }

                Divider()
                HStack {
                    Text("Total").foregroundStyle(.secondary)
                    Spacer()
                    Text(currencyString(fromCents: invoice.totalCents))
                }
                .font(.subheadline)
                HStack {
                    Text("Balance due").font(.headline)
                    Spacer()
                    Text(currencyString(fromCents: invoice.balanceDueCents))
                        .font(.headline)
                        .foregroundStyle(invoiceStage == .overdue ? Color.red : Color.primary)
                }
            }
            .sbwCardRow()
        }
    }

    private func paymentRow(title: String, detail: String, amountCents: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(currencyString(fromCents: amountCents))
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var InvoiceMoreSections: some View {
        if isPricingLocked {
            Section {
                Label(
                    invoice.isPaid ? "Paid invoices are locked." : "Sent invoices lock pricing. Unlock it from the ••• menu to correct and resend.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }

        Section {
            DisclosureGroup(isExpanded: $showInvoiceDetails) {
                InvoiceEssentialsSection
            } label: {
                Label("Details", systemImage: "square.and.pencil").font(.headline)
            }
            .sbwCardRow()
        }

        Section {
            DisclosureGroup(isExpanded: $showInvoiceNotes) {
                advancedPaymentCard
                advancedNotesCard
                advancedThankYouCard
                advancedTermsCard
            } label: {
                Label("Notes and Terms", systemImage: "note.text").font(.headline)
            }
            .sbwCardRow()
        }

        Section {
            DisclosureGroup(isExpanded: $showInvoiceAttachments) {
                advancedAttachmentsHeaderCard
                attachmentRows
            } label: {
                HStack {
                    Label("Attachments", systemImage: "paperclip").font(.headline)
                    Spacer()
                    Text("\(attachments.count)").foregroundStyle(.secondary)
                }
            }
            .sbwCardRow()
        }

        Section {
            DisclosureGroup(isExpanded: $showInvoiceActivity) {
                invoiceActivityCard
                advancedAuditCard
                advancedPortalDetailsCard
            } label: {
                Label("Activity and Portal", systemImage: "clock.arrow.circlepath").font(.headline)
            }
            .sbwCardRow()
        }
    }

    private var invoiceActivityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            activityLine("Created", invoice.issueDate)
            if let sentAt = invoice.sentAt { activityLine("Sent", sentAt) }
            if let viewedAt = invoice.viewedAt { activityLine("Viewed by client", viewedAt) }
            if let reminded = invoice.lastReminderAt { activityLine("Last reminder", reminded) }
            ForEach((invoice.payments ?? []).sorted { $0.paidAt < $1.paidAt }) { payment in
                activityLine("Paid \(currencyString(fromCents: payment.amountCents))", payment.paidAt)
            }
            if invoice.wasSent {
                Text(portalSyncStatusText)
                    .font(.caption)
                    .foregroundStyle(invoice.portalLastUploadError == nil ? Color.secondary : Color.red)
            }
        }
        .sbwCardRow()
    }

    private func activityLine(_ label: String, _ date: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var invoiceToolbarButtons: some View {
        Button {
            handleDoneTapped()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")

        Button { previewPDF() } label: { Image(systemName: "doc.richtext") }
            .accessibilityLabel("Preview PDF")

        Menu {
            if invoice.wasSent && !invoice.isPaid {
                Button { invoiceSendKind = .reminder } label: { Label("Send Reminder", systemImage: "bell") }
                Button { copyClientLink() } label: { Label("Copy Client Link", systemImage: "doc.on.doc") }
            }
            if invoiceStage != .paid && invoice.totalCents > 0 {
                Button { showRecordPayment = true } label: { Label("Record Payment", systemImage: "banknote") }
            }
            if isPricingLocked && !invoice.isPaid {
                Button { confirmUnlockPricing = true } label: { Label("Unlock Pricing", systemImage: "lock.open") }
            }

            Divider()

            Menu {
                Button("PDF Only") { sharePDFOnly() }
                Button("PDF + Attachments") { sharePDFWithAttachments() }
                Button("ZIP Package (PDF + Attachments)") { shareZIPPackage() }
                Button("Attachments ZIP") { shareAttachmentsZIPOnly() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button { emailPDF() } label: { Label("Email PDF", systemImage: "envelope") }
            Button { duplicateInvoice() } label: { Label(duplicateActionTitle, systemImage: "doc.on.doc") }
            if invoice.client?.portalEnabled == true {
                Button { makeRecurring() } label: { Label("Make Recurring", systemImage: "arrow.triangle.2.circlepath") }
            }
            Button { showTemplatePicker = true } label: { Label("Change Template", systemImage: "paintpalette") }
            Button { openJobWorkspaceFolder() } label: { Label("Job Files", systemImage: "folder") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .confirmationDialog("Unlock pricing?", isPresented: $confirmUnlockPricing, titleVisibility: .visible) {
            Button("Unlock Pricing") { pricingUnlocked = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(invoiceClientName) already has this invoice. After you change it, resend it so they see the new amount — their portal updates when you tap Done.")
        }
    }

    // MARK: - Estimate layout
    //
    // An estimate gets one screen built around what happens next: a status
    // track in the header, then a card with the one action for its stage —
    // send it, wait on the client, act on their answer, or revise after a
    // decline. What used to hide in Advanced Options (status, contract,
    // convert) is on the page; notes, attachments and history collapse
    // below. Invoices keep the layout above.

    private var estimateStage: String {
        let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["sent", "accepted", "declined"].contains(status) ? status : "draft"
    }

    private var estimateClientName: String {
        let name = (invoice.clientForRendering?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "your client" : name
    }

    private var estimateClientEmail: String {
        (invoice.client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The invoice this estimate was converted to, if any, so Convert isn't
    /// offered twice.
    private var convertedInvoiceForEstimate: Invoice? {
        let sourceID = invoice.id.uuidString
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.sourceEstimateId == sourceID && $0.documentType == "invoice" }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private var estimateStatusTrack: some View {
        let stage = estimateStage
        let reached: Int = stage == "draft" ? 1 : stage == "sent" ? 2 : 3
        let decisionLabel = stage == "accepted" ? "Accepted" : stage == "declined" ? "Declined" : "Decision"
        let decisionColor: Color = stage == "declined" ? .red : stage == "accepted" ? SBWTheme.brandGreen : SBWTheme.brandBlue

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < reached ? (index == 2 ? decisionColor : SBWTheme.brandBlue) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Draft")
                Spacer()
                Text("Sent")
                Spacer()
                Text(decisionLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(invoiceStatusText)")
    }

    private var EstimateNextStepSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next step")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SBWTheme.brandBlue)

                switch estimateStage {
                case "sent": estimateSentStep
                case "accepted": estimateAcceptedStep
                case "declined": estimateDeclinedStep
                default: estimateDraftStep
                }

                if let portalNotice {
                    Text(portalNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let portalErrorMessage = portalError {
                    portalErrorRow(portalErrorMessage)
                }
            }
            .sbwCardRow()
            .confirmationDialog(
                estimateStage == "draft" ? "Send this estimate?" : "Resend this estimate?",
                isPresented: $confirmSendEstimate,
                titleVisibility: .visible
            ) {
                Button(estimateStage == "draft" ? "Send Estimate" : "Resend Estimate") { sendEstimate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(EstimateSendService.confirmationMessage(for: invoice))
            }
            .confirmationDialog(
                "Record \(estimateClientName)'s answer",
                isPresented: $confirmRecordAnswer,
                titleVisibility: .visible
            ) {
                Button("They accepted") { acceptEstimateAndCreateJob() }
                Button("They declined", role: .destructive) { recordEstimateDeclined() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("For an answer you got another way, like a phone call. Accepting creates the job, the same as when a client accepts in the portal.")
            }
        }
    }

    @ViewBuilder
    private var estimateDraftStep: some View {
        if invoice.client == nil {
            estimateStepTitle("Choose a client", detail: "Pick who this estimate is for in Details below.")
        } else if estimateClientEmail.isEmpty {
            estimateStepTitle("Add an email for \(estimateClientName)", detail: "The estimate is emailed to your client with a link to accept or decline.")
            Button { navigateToClientSettings = invoice.client } label: {
                Label("Edit Client", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
        } else if !isClientPortalEnabled {
            estimateStepTitle("Turn on the client portal", detail: "\(estimateClientName) reviews and answers estimates in their client portal.")
            Button { navigateToClientSettings = invoice.client } label: {
                Label("Enable Client Portal", systemImage: "togglepower")
            }
            .buttonStyle(.bordered)
        } else {
            estimateStepTitle(
                "Send it to \(estimateClientName)",
                detail: "Emails \(estimateClientEmail) a link to review, accept or decline."
            )
            HStack(spacing: 10) {
                sendEstimateButton(title: "Send Estimate", prominent: true)
                Button { previewPDF() } label: { Label("Preview", systemImage: "doc.richtext") }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var estimateSentStep: some View {
        estimateStepTitle(
            "Waiting on \(estimateClientName)",
            detail: "You'll get a notification when they respond."
        )
        HStack(spacing: 10) {
            Button { openClientPortal() } label: {
                if openingPortal {
                    ProgressView()
                } else {
                    Label("View in Portal", systemImage: "rectangle.and.hand.point.up.left")
                }
            }
            .buttonStyle(.bordered)
            .disabled(openingPortal)

            Button { copyClientLink() } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                .buttonStyle(.bordered)
                .disabled(openingPortal)
        }
        sendEstimateButton(title: "Resend Estimate", prominent: false)

        Button("Client answered another way? Record their answer") {
            confirmRecordAnswer = true
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(SBWTheme.brandBlue)
    }

    @ViewBuilder
    private var estimateAcceptedStep: some View {
        estimateStepTitle(
            estimateStatusTimestampText ?? "Accepted",
            detail: "Schedule the work and bill for it."
        )
        HStack(spacing: 10) {
            if let job = invoice.job {
                Button { estimateJobRoute = job } label: { Label("Open Job", systemImage: "hammer") }
                    .sbwProminentButton()
            } else {
                Button { acceptEstimateAndCreateJob() } label: { Label("Create Job", systemImage: "hammer.fill") }
                    .sbwProminentButton()
                    .disabled(invoice.client == nil)
            }

            if let converted = convertedInvoiceForEstimate {
                Button { invoiceOverviewRoute = converted } label: {
                    Label("Open Invoice", systemImage: "doc.plaintext")
                }
                .buttonStyle(.bordered)
            } else {
                Button { convertEstimateToInvoice() } label: {
                    Label("Convert to Invoice", systemImage: "arrow.right.doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var estimateDeclinedStep: some View {
        estimateStepTitle(
            estimateStatusTimestampText ?? "Declined",
            detail: "Adjust the price or scope, then send it again."
        )
        Button { reopenDeclinedEstimate() } label: {
            Label("Revise and Resend", systemImage: "arrow.uturn.backward")
        }
        .sbwProminentButton()
    }

    private func estimateStepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var EstimateContractSection: some View {
        Section {
            advancedContractCard
                .disabled(isEstimateLocked)
        }
        if linkedEstimateContracts.count > 1 {
            Section {
                advancedLinkedContractsCard
            }
        }
    }

    @ViewBuilder
    private var EstimateMoreSections: some View {
        Section {
            DisclosureGroup(isExpanded: $showEstimateNotes) {
                advancedPaymentCard.disabled(isEstimateLocked)
                advancedNotesCard.disabled(isEstimateLocked)
                advancedThankYouCard.disabled(isEstimateLocked)
                advancedTermsCard.disabled(isEstimateLocked)
            } label: {
                Label("Notes and Terms", systemImage: "note.text")
                    .font(.headline)
            }
            .sbwCardRow()
        }

        Section {
            DisclosureGroup(isExpanded: $showEstimateAttachments) {
                advancedAttachmentsHeaderCard
                attachmentRows
            } label: {
                HStack {
                    Label("Attachments", systemImage: "paperclip")
                        .font(.headline)
                    Spacer()
                    Text("\(attachments.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .sbwCardRow()
        }

        Section {
            DisclosureGroup(isExpanded: $showEstimateActivity) {
                if estimateStage != "draft" {
                    Text(portalSyncStatusText)
                        .font(.caption)
                        .foregroundStyle(invoice.portalLastUploadError == nil ? Color.secondary : Color.red)
                        .sbwCardRow()
                }
                advancedAuditCard
                advancedPortalDetailsCard
            } label: {
                Label("Activity and Portal", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
            }
            .sbwCardRow()
        }
    }

    @ViewBuilder
    private var estimateToolbarButtons: some View {
        Button {
            handleDoneTapped()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")

        Button { previewPDF() } label: { Image(systemName: "doc.richtext") }
            .accessibilityLabel("Preview PDF")

        Menu {
            Button {
                renameEstimateText = invoice.invoiceNumber
                showRenameEstimate = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { showTemplatePicker = true } label: {
                Label("Change Template", systemImage: "paintpalette")
            }
            Button { openJobWorkspaceFolder() } label: {
                Label("Job Files", systemImage: "folder")
            }

            Divider()

            Menu {
                Button("PDF Only") { sharePDFOnly() }
                Button("PDF + Attachments") { sharePDFWithAttachments() }
                Button("ZIP Package (PDF + Attachments)") { shareZIPPackage() }
                Button("Attachments ZIP") { shareAttachmentsZIPOnly() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button { emailPDF() } label: {
                Label("Email PDF", systemImage: "envelope")
            }
            Button { duplicateInvoice() } label: {
                Label(duplicateActionTitle, systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private func openClientPortal() {
        Task {
            openingPortal = true
            portalError = nil
            portalNotice = nil
            do {
                portalURL = try await buildPortalLink(mode: nil)
                showPortal = true
            } catch {
                portalURL = nil
                portalError = error.localizedDescription
            }
            openingPortal = false
        }
    }

    private func copyClientLink() {
        Task {
            openingPortal = true
            portalError = nil
            portalNotice = nil
            do {
                let url = try await buildPortalLink(mode: nil)
                UIPasteboard.general.string = url.absoluteString
                showNotice("Client link copied")
            } catch {
                portalError = error.localizedDescription
            }
            openingPortal = false
        }
    }

    private func recordEstimateDeclined() {
        invoice.estimateStatus = "declined"
        invoice.estimateDeclinedAt = .now
        invoice.estimateAcceptedAt = nil
        try? modelContext.save()
    }

    private func reopenDeclinedEstimate() {
        EstimateDecisionSync.reopenDeclinedEstimate(invoice, in: modelContext)
        portalError = nil
        showNotice("Back to draft. Make your changes, then send it again.")
    }

    @ViewBuilder
    private var attachmentRows: some View {
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
    }

    private var invoiceDisplayTitle: String {
        let num = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = invoice.documentType == "estimate" ? "Estimate" : "Invoice"
        return num.isEmpty ? base : "\(base) \(num)"
    }

    private var duplicateActionTitle: String {
        invoice.documentType == "estimate" ? "Duplicate Estimate" : "Duplicate Invoice"
    }

    private var invoiceStatusText: String {
        if invoice.documentType == "estimate" {
            return estimateStatusText
        }
        switch invoiceStage {
        case .draft: return "DRAFT"
        case .sent: return "SENT"
        case .overdue: return "OVERDUE"
        case .partPaid: return "PART PAID"
        case .paid: return "PAID"
        }
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

    @ViewBuilder
    private func sendEstimateButton(title: String, prominent: Bool) -> some View {
        let button = Button {
            confirmSendEstimate = true
        } label: {
            if sendingEstimate {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sending…")
                }
            } else {
                Label(title, systemImage: "paperplane.fill")
            }
        }
        .disabled(sendingEstimate || openingPortal || !invoice.canBeSent)

        if prominent {
            button.sbwProminentButton()
        } else {
            button.buttonStyle(.bordered).tint(SBWTheme.brandBlue)
        }

        if let reason = invoice.cannotBeSentReason {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sendEstimate() {
        guard !sendingEstimate else { return }
        sendingEstimate = true
        portalError = nil
        portalNotice = nil
        forceSaveNow()

        Task {
            defer { sendingEstimate = false }
            do {
                switch try await EstimateSendService.send(
                    estimate: invoice,
                    context: modelContext,
                    businessName: resolvedPortalBusinessName()
                ) {
                case .emailed(let email):
                    Haptics.success()
                    showNotice("Estimate sent to \(email)")
                case .publishedNotEmailed(let link, _):
                    if let link { UIPasteboard.general.string = link }
                    portalError = link == nil
                        ? "The estimate is in your client's portal, but the email didn't go out. Use Resend to try again."
                        : "The estimate is in your client's portal, but the email didn't go out. Its link is copied — paste it to your client, or use Resend."
                }
            } catch {
                portalError = error.localizedDescription
            }
        }
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

            if let lockText = invoice.businessInfoLockStatusText {
                Text(lockText)
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Draft invoices use your current Business Profile.")
                    .foregroundStyle(.secondary)
            }

            if invoice.canRefreshBusinessInfo {
                Button("Refresh Business Info") {
                    Task { await refreshBusinessSnapshotIfAllowed() }
                }
                .buttonStyle(.bordered)
            }

            if let businessInfoNotice {
                Text(businessInfoNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var linkedEstimateContracts: [Contract] {
        var seen = Set<UUID>()
        var result: [Contract] = []
        for c in (invoice.estimateContracts ?? []) + (invoice.contracts ?? []) {
            guard seen.insert(c.id).inserted else { continue }
            result.append(c)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    private var advancedContractCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contract")
                .font(.headline)

            if let first = linkedEstimateContracts.first {
                Button {
                    createdContract = first
                } label: {
                    Label("Open Contract", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Text("A contract is already attached to this estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let depositCents = first.depositAmountCents {
                    Text("Deposit required: \(currencyString(fromCents: depositCents)) — due before the job starts, not before signing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            } else {
                Text("Draft the contract now, alongside the estimate — it stays private until the estimate is approved, then it's automatically sent for signature. Optional; skip if this job doesn't need one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if contractTemplates.isEmpty {
                    Text("No contract templates found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Template", selection: $selectedContractTemplate) {
                        Text("Select a template…").tag(Optional<ContractTemplate>.none)
                        ForEach(contractTemplates) { t in
                            Text("\(t.name) (\(t.category))").tag(Optional(t))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    HStack {
                        Text("Deposit (optional)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $depositAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }

                    Button {
                        draftBundledContract()
                    } label: {
                        Label("Draft Contract for this Estimate", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedContractTemplate == nil)
                }
            }
        }
        .sbwCardRow()
    }

    private var advancedLinkedContractsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Contracts")
                .font(.headline)

            let contracts = linkedEstimateContracts

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

        if invoice.isUnsentEstimate {
            throw NSError(
                domain: "Portal",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Send this estimate before opening it in the client portal."]
            )
        }

        if isClientPortalEnabled == false {
            throw NSError(
                domain: "Portal",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Client portal is disabled for this client."]
            )
        }

        let amountCents = invoice.totalCents
        guard amountCents > 0 else {
            throw NSError(
                domain: "Portal",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey:
                    "This invoice total is $0.00. Add line items / amount before requesting payment."
                ]
            )
        }

        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: modelContext,
            reason: .portal,
            replaceExistingUnlockedSnapshot: !invoice.isBusinessInfoLocked
        )

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
            let created = try EstimateToInvoiceConverter.convert(
                estimate: invoice,
                profiles: profiles,
                context: modelContext
            )
            if created.id != invoice.id {
                invoiceOverviewRoute = created
            }
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
            Task { await indexInvoiceIfPossible() }
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Toolbar / Sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Only where something provides it; elsewhere it was a button that
        // did nothing.
        if dismissToDashboard != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismissToDashboard?()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Home")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if invoice.documentType == "estimate" {
                estimateToolbarButtons
            } else {
                invoiceToolbarButtons
            }
        }
    }

    private var itemPickerSheet: some View {
        NavigationStack {
            ItemPickerView(businessID: invoice.businessID) { picked in
                let desc = CatalogItemAutoSaveService.combineLineItemDescription(
                    name: picked.name,
                    details: picked.details
                )

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
                    attachmentFileName: mailFilename.isEmpty ? InvoicePDFGenerator.preferredPDFFileName(for: invoice) : mailFilename
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
        guard invoice.isBusinessInfoLocked else { return }
        guard invoice.businessSnapshotData == nil else { return }
        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: modelContext,
            reason: invoice.isPaid ? .paid : .historical,
            replaceExistingUnlockedSnapshot: false
        )
    }

    @MainActor
    private func refreshBusinessSnapshotIfAllowed() async {
        guard invoice.canRefreshBusinessInfo else { return }
        _ = InvoicePDFService.refreshBusinessInfoForDraft(
            invoice: invoice,
            context: modelContext
        )
        Haptics.success()
        showBusinessInfoNotice("Business info refreshed")
    }

    @MainActor
    private func showBusinessInfoNotice(_ text: String) {
        businessInfoNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if businessInfoNotice == text { businessInfoNotice = nil }
        }
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
    
    /// Drafts a contract bundled with this estimate, rendered from a real
    /// template (client name, line items, total — via ContractCreation.create)
    /// rather than the old bare, unrendered Contract(). Doesn't require a Job
    /// to exist yet — a job gets linked automatically once the estimate is
    /// accepted. Stays in .draft, invisible to the client, until
    /// EstimateAcceptancePullService.materialize activates it on acceptance.
    private func draftBundledContract() {
        exportError = nil
        guard let template = selectedContractTemplate else { return }

        let bizID = invoice.businessID
        let business = profiles.first(where: { $0.businessID == bizID })

        do {
            let contract = try ContractCreation.create(
                context: modelContext,
                template: template,
                businessID: bizID,
                business: business,
                client: invoice.client,
                invoice: invoice
            )
            contract.job = invoice.job
            contract.depositAmountCents = parsedDepositAmountCents()
            try? modelContext.save()
            createdContract = contract
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// nil when the field is empty or not a usable positive amount — a
    /// deposit is optional, so an unparsable/blank entry just means "no
    /// deposit," not an error.
    private func parsedDepositAmountCents() -> Int? {
        let trimmed = depositAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let dollars = Double(trimmed), dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }
    
    private var isEstimateLocked: Bool {
        guard invoice.documentType == "estimate" else { return false }
        return linkedEstimateContracts.contains(where: { $0.status == .signed })
    }

    private var isEstimateAcceptedLocked: Bool {
        guard invoice.documentType == "estimate" else { return false }
        return invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "accepted"
    }

    private var isEstimatePricingLocked: Bool {
        isEstimateLocked || isEstimateAcceptedLocked
    }

    /// Estimates lock once accepted or their contract is signed; invoices
    /// once sent — the client may already have paid against those numbers —
    /// unless the owner unlocked pricing from the menu to correct and resend.
    private var isPricingLocked: Bool {
        if invoice.documentType == "estimate" { return isEstimatePricingLocked }
        return (invoice.wasSent || invoice.isPaid) && !pricingUnlocked
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
        Task { @MainActor in await emailPDFAsync() }
    }

    private func emailPDFAsync() async {
        do {
            let pdfData = await InvoicePDFService.makePDFDataOffMainThread(
                invoice: invoice,
                profiles: profiles,
                context: modelContext,
                businesses: businesses,
                lockBusinessSnapshot: true,
                lockReason: .sent
            )

            mailAttachment = pdfData
            mailFilename = InvoicePDFGenerator.preferredPDFFileName(for: invoice)

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
        do {
            let copy = try InvoiceDuplicationService.duplicate(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            Haptics.success()
            invoiceOverviewRoute = copy
        } catch {
            Haptics.error()
            exportError = error.localizedDescription
        }
    }

    /// Snapshots this invoice's line items and terms into a new recurring
    /// schedule, opened as a draft so the owner confirms cadence and next
    /// run date before it starts generating anything.
    private func makeRecurring() {
        guard let client = invoice.client, client.portalEnabled else {
            exportError = "Enable Client Portal for this client first — recurring invoices are sent through the portal."
            return
        }

        let schedule = RecurringInvoiceSchedule(
            businessID: invoice.businessID,
            clientID: client.id,
            nextRunAt: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        )
        schedule.lineItems = (invoice.items ?? []).map {
            RecurringScheduleLineItem(
                itemDescription: $0.itemDescription,
                quantity: $0.quantity,
                unitPrice: $0.unitPrice
            )
        }
        schedule.taxRatePercent = invoice.taxRate * 100
        schedule.discountAmount = invoice.discountAmount

        modelContext.insert(schedule)
        do {
            try modelContext.save()
        } catch {
            exportError = error.localizedDescription
            modelContext.delete(schedule)
            return
        }

        Haptics.lightTap()
        newRecurringScheduleDraft = schedule
        showingNewRecurringSchedule = true
    }

    private func persistInvoicePDFToJobFiles(lockReason: BusinessSnapshotLockReason = .sent) throws -> URL {
        return try DocumentFileIndexService.persistInvoicePDF(
            invoice: invoice,
            profiles: profiles,
            context: modelContext,
            lockReason: lockReason
        )
    }

    // MARK: - Share actions

    private func shareFromPreview(url: URL) {
        do {
            let officialURL = try persistInvoicePDFToJobFiles(lockReason: .sent)
            var items: [Any] = [officialURL]
            items.append(contentsOf: attachmentURLsForInvoice())
            shareItems = items
        } catch {
            var items: [Any] = [url]
            items.append(contentsOf: attachmentURLsForInvoice())
            shareItems = items
            exportError = error.localizedDescription
        }
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
        _ = suffix
        let filename = InvoicePDFGenerator.preferredPDFBaseName(for: invoice)
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
                // Only a client's decision comes from the portal. Whether an
                // estimate was sent is this device's call (EstimateSendService)
                // — taking "sent" from here flipped drafts to sent when the
                // backend guessed at a record's status.
                return
            }
            try? modelContext.save()
        } catch {
            SBWLog.ui.problem("Estimate status refresh failed: \(error.localizedDescription)")
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
                _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                    invoice: invoice,
                    profiles: profiles,
                    context: modelContext,
                    reason: .paid,
                    replaceExistingUnlockedSnapshot: !invoice.isBusinessInfoLocked
                )
                invoice.isPaid = true
                try? modelContext.save()
            }
        } catch {
            // Optional: show a non-blocking error
            // portalError = "Couldn’t refresh payment status"
            SBWLog.ui.problem("Payment status refresh failed: \(error)")
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
            SBWLog.ui.problem("Manual reports refresh failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func resolveManualReport(reportId: String, action: String) async {
        guard resolvingManualReportId == nil else { return }
        resolvingManualReportId = reportId
        defer { resolvingManualReportId = nil }

        do {
            try await PortalPaymentsAPI.shared.resolveManualPaymentReport(reportId: reportId, action: action)
            // Approving settles it on the server; record what the client said
            // they paid so the payments list and balance match.
            if action == "approve",
               let report = manualReports.first(where: { $0.id == reportId }),
               !(invoice.payments ?? []).contains(where: { $0.source == "portal" }) {
                _ = try? InvoicePaymentService.record(
                    on: invoice,
                    amountCents: report.amountCents,
                    paidAt: Date(timeIntervalSince1970: TimeInterval(report.createdAtMs) / 1000),
                    method: report.method.lowercased(),
                    note: report.reference.map { "Ref \($0)" } ?? "Reported by client",
                    source: "portal",
                    context: modelContext
                )
            }
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

        let zipName = "\(InvoicePDFGenerator.preferredPDFBaseName(for: invoice))_package_\(Int(Date().timeIntervalSince1970)).zip"
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

// Froze the app when a line item was tapped. This screen is itself a
// navigationDestination (of the invoice/estimate summary and others), so
// pushing a line item made NavigationStack re-resolve its destinations and
// rebuild this view. With @Query and @State inside, SwiftUI can't compare the
// rebuilt value field-by-field, so it re-rendered — which re-published this
// screen's own destinations and rebuilt it again (~400 renders/sec). Same
// class of bug as AttachmentsManagerView. The invoice is the only input; its
// edits, queries and state drive their own updates.
extension InvoiceDetailView: Equatable {
    static func == (lhs: InvoiceDetailView, rhs: InvoiceDetailView) -> Bool {
        lhs.invoice.persistentModelID == rhs.invoice.persistentModelID
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
