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

    // Job picker
    @State private var showJobPicker = false
    
    @State private var portalURL: URL? = nil
    @State private var portalError: String? = nil
    @State private var portalNotice: String? = nil
    @State private var openingPortal = false
    @State private var uploadingPortalPDF = false
    @State private var portalPDFNotice: String? = nil


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

        Form {
            clientSection
            jobSection
            estimateWorkflowSection
            
            if invoice.documentType == "estimate" {
                contractFromEstimateSection
                linkedContractsOnEstimateSection
            }


            // ✅ STEP 4: Convert section (only for estimates)
            if invoice.documentType == "estimate" && invoice.estimateStatus == "accepted" {
                convertSection
            }

            datesSection
            paymentSection
            portalSection
            notesSection
            thankYouSection
            termsSection
            chargesSection
            lineItemsSection
            totalsSection
            auditSnapshotSection
            statusSection
            attachmentsSection
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        
        .navigationDestination(item: $createdContract) { c in
            ContractDetailView(contract: c)
        }
        
        .sheet(isPresented: $showPortal, onDismiss: {
            Task { await refreshInvoicePaidStatusFromPortal() }
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
            Task { await refreshInvoicePaidStatusFromPortal() }
        }
        .task {
            await ensureSnapshotForFinalizedInvoiceIfNeeded()
        }
        .onChange(of: invoice.estimateStatus) { _, _ in
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
        }
        .onChange(of: invoice.invoiceNumber) { _, _ in
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
        }
        .onChange(of: invoice.documentType) { _, _ in
            Task { await ensureSnapshotForFinalizedInvoiceIfNeeded() }
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

    private var clientSection: some View {
        Section("Client") {
            Text(invoice.client?.name ?? "No Client Selected")
                .foregroundStyle(invoice.client == nil ? .secondary : .primary)

            NavigationLink("Select / Edit Client") {
                ClientPickerManualFetchView(selectedClient: $invoice.client)
            }
        }
    }

    private var jobSection: some View {
        Section("Job / Project") {
            HStack {
                Text("Job")
                Spacer()
                Text(invoice.job?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? (invoice.job?.title ?? "")
                     : "None")
                    .foregroundStyle(invoice.job == nil ? .secondary : .primary)
                    .lineLimit(1)
            }

            Button("Select Job") { showJobPicker = true }

            if invoice.job != nil {
                Button(role: .destructive) {
                    invoice.job = nil
                    try? modelContext.save()
                } label: {
                    Text("Clear Job")
                }
            }
        }
    }

    // ✅ STEP 4: Convert section
    private var convertSection: some View {
        Section("Estimate") {
            if invoice.estimateStatus != "accepted" {
                Text("Accept this estimate before converting to an invoice.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    convertEstimateToInvoice()
                } label: {
                    Label("Convert to Invoice", systemImage: "arrow.right.doc.on.clipboard")
                }
            }
        }
    }
    
    private var contractFromEstimateSection: some View {
        Section("Contract") {
            let existing = (invoice.estimateContracts ?? [])
            let first = existing.first

            if invoice.job == nil {
                Text("Link or create a Job first to generate a contract.")
                    .foregroundStyle(.secondary)

            } else if let first {
                Button {
                    // ✅ state-driven navigation avoids the SwiftData NavigationLink hang
                    createdContract = first
                } label: {
                    Label("Open Contract", systemImage: "doc.text")
                }

                Text("A contract already exists for this estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else {
                Button {
                    createContractFromEstimate()
                } label: {
                    Label("Create Contract for this Job", systemImage: "doc.badge.plus")
                }
            }
        }
    }


   
    private var linkedContractsOnEstimateSection: some View {
        Section("Linked Contracts") {
            let contracts = (invoice.estimateContracts ?? [])

            if contracts.isEmpty {
                Text("No contracts linked to this estimate yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contracts) { c in
                    NavigationLink {
                        ContractDetailView(contract: c)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title.isEmpty ? "Contract" : c.title)
                                Text(statusLabel(c.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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

        // Best-effort: upload the latest invoice PDF so the portal can offer a Download PDF button.
        // If upload fails, we still allow the portal link to be generated.
        do {
            uploadingPortalPDF = true
            portalPDFNotice = nil

            let snapshot = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            let pdfData = InvoicePDFGenerator.makePDFData(invoice: invoice, business: snapshot)
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
            // Non-blocking
            print("Portal PDF upload failed:", error)
        }
        uploadingPortalPDF = false

        if invoice.documentType == "estimate",
           invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "draft" {
            invoice.estimateStatus = "sent"
            try? modelContext.save()
            await ensureSnapshotForFinalizedInvoiceIfNeeded()
        }

        let token = try await PortalBackend.shared.createInvoicePortalToken(invoice: invoice, businessName: businessName)

        let modeValue = (mode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? mode!
            : "live"

        let url = PortalBackend.shared.portalInvoiceURL(
            invoiceId: invoice.id.uuidString,
            token: token,
            mode: modeValue
        )
        return url
    }
    

    @MainActor
    private func showNotice(_ text: String) {
        portalNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if portalNotice == text { portalNotice = nil }
        }
    }


    private var datesSection: some View {
        Section("Dates") {
            DatePicker("Issue Date", selection: $invoice.issueDate, displayedComponents: .date)
            DatePicker("Due Date", selection: $invoice.dueDate, displayedComponents: .date)
        }
    }

    private var paymentSection: some View {
        Section("Payment") {
            TextField(
                "Payment Terms",
                text: $invoice.paymentTerms,
                prompt: Text("e.g. Due on receipt, Net 14")
            )
        }
        .disabled(isEstimateLocked)
    }
    
        private var isClientPortalEnabled: Bool {
        invoice.client?.portalEnabled ?? true
    }

private var isPortalExpiredForThisInvoice: Bool {
        portalReturn.expiredInvoiceID == invoice.id
    }

    private var portalSection: some View {
        Section("Client Portal") {
            if !isClientPortalEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "nosign")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Client portal is disabled for this client.")
                            .font(.caption)

                        Text("Enable it in the client’s settings to generate a new portal link.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if isPortalExpiredForThisInvoice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("This client link has expired.")
                            .font(.caption)

                        Button("Regenerate link") {
                            guard isClientPortalEnabled else { return }

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
                        }
                        .font(.caption.weight(.semibold))
                    }

                    Spacer()
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        // Small polish: if already paid, label it as such
                        if invoice.isPaid {
                            Label("View Client Portal (Paid)", systemImage: "checkmark.seal")
                        } else {
                            Label("View in Client Portal", systemImage: "rectangle.and.hand.point.up.left")
                        }
                    }
                }
                .disabled(openingPortal || !isClientPortalEnabled)
                .opacity((openingPortal || !isClientPortalEnabled) ? 0.6 : 1)

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
                                // Reuse your existing ShareSheet plumbing
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

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.vertical, 6)
                }
                .disabled(openingPortal || !isClientPortalEnabled)
                .opacity((openingPortal || !isClientPortalEnabled) ? 0.6 : 1)
            }

            if let portalNotice {
                Text(portalNotice)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if let portalPDFNotice {
                Text(portalPDFNotice)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if let issuerName = resolvedPortalBusinessName() {
                Text("Issued by: \(issuerName)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if isSnapshotLockedForInvoice {
                Text("PDF matches portal copy")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }

            if let portalErrorMessage = portalError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(portalErrorMessage)
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

            // Optional microcopy (nice polish)
            Text("Client links expire after 30 days.")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }
    
    private var notesSection: some View {
        Section("Notes") {
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
        .disabled(isEstimateLocked)
    }

    private var thankYouSection: some View {
        Section("Thank You") {
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
        .disabled(isEstimateLocked)
    }

    private var termsSection: some View {
        Section("Terms & Conditions") {
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
        .disabled(isEstimateLocked)
    }

    private var chargesSection: some View {
        Section("Charges") {
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
        }
        .disabled(isEstimateLocked)
    }

    private var lineItemsSection: some View {
        Section("Line Items") {
            Button { showingItemPicker = true } label: {
                Label("Add From Saved Items", systemImage: "tray.and.arrow.down")
            }

            ForEach(invoice.items ?? []) { item in
                NavigationLink {
                    LineItemEditView(item: item)
                } label: {
                    lineItemRow(item)
                }
            }
            .onDelete(perform: deleteItems)

            Button { addItem() } label: {
                Label("Add Line Item", systemImage: "plus.circle")
            }
        }
        .disabled(isEstimateLocked)
    }

    private func lineItemRow(_ item: LineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.itemDescription.isEmpty ? "Item" : item.itemDescription)
                .font(.headline)
            HStack {
                Text("\(item.quantity, format: .number) × \(item.unitPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.lineTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private var totalsSection: some View {
        Section("Totals") {
            totalRow("Subtotal", invoice.subtotal)
            totalRow("Discount", -invoice.discountAmount)
            totalRow("Tax", invoice.taxAmount)
            Divider()
            totalRow("Total", invoice.total, isEmphasis: true)
        }
        .disabled(isEstimateLocked)
    }

    private var auditSnapshotSection: some View {
        Section("Audit / Snapshot") {
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
            }
        }
    }
    private var estimateWorkflowSection: some View {
        Group {
            if invoice.documentType == "estimate" {
                Section("Estimate Workflow") {

                    Picker("Status", selection: $invoice.estimateStatus) {
                        Text("Draft").tag("draft")
                        Text("Sent").tag("sent")
                        Text("Accepted").tag("accepted")
                        Text("Declined").tag("declined")
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
                        }
                    } else {
                        Button {
                            invoice.estimateStatus = "accepted"
                            invoice.estimateAcceptedAt = Date()
                            acceptEstimateAndCreateJob()
                        } label: {
                            Label("Accept & Create Job", systemImage: "checkmark.seal.fill")
                        }
                        .disabled(invoice.client == nil) // strongly recommended
                    }

                    if invoice.client == nil {
                        Text("Select a customer first to create the Job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func acceptEstimateAndCreateJob() {
        exportError = nil

        // If already linked, do nothing
        if invoice.job != nil { return }

        do {
            // You already use this in openJobWorkspaceFolder()
            let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)

            // ✅ Create a new Job (match your Job initializer)
            // IMPORTANT: if your Job init signature differs, adjust ONLY this block.
            let titleBase = invoice.client?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeClient = (titleBase?.isEmpty == false) ? titleBase! : "Client"
            let jobTitle = "Job - \(safeClient)"

            // ---- Job creation (adjust if needed to match your Job model) ----
            let job = Job(
                businessID: biz.id,
                clientID: invoice.client?.id,
                title: jobTitle,
                notes: "Created from estimate \(invoice.invoiceNumber)",
                startDate: invoice.issueDate,
                endDate: invoice.dueDate,
                locationName: "",
                latitude: nil,
                longitude: nil,
                status: "scheduled"
            )
            // ---------------------------------------------------------------

            modelContext.insert(job)

            // Link estimate → job
            invoice.job = job
            invoice.businessID = biz.id


            // Mark accepted if not already
            if invoice.estimateStatus != "accepted" {
                invoice.estimateStatus = "accepted"
                invoice.estimateAcceptedAt = Date()
            }

            try modelContext.save()

        } catch {
            exportError = error.localizedDescription
        }
    }



    private var statusSection: some View {
        Section("Status") {
            Toggle("Mark as Paid", isOn: $invoice.isPaid)
        }
    }

    private var attachmentsSection: some View {
        Section("Attachments") {
            if attachments.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(.secondary)
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
                    .swipeActions {
                        Button(role: .destructive) {
                            removeAttachment(a)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            HStack {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Attach Existing File", systemImage: "paperclip")
                }

                Spacer()

                Menu {
                    Button("Import from Files") { showInvoiceAttachmentFileImporter = true }
                    Button("Import from Photos") { showInvoiceAttachmentPhotosSheet = true }
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - STEP 4 helper

    private func convertEstimateToInvoice() {
        let profile = resolvedBusinessProfile()
        guard let profile else {
            exportError = "Business Profile is missing. Create one first."
            return
        }

        // Year rollover logic
        let year = Calendar.current.component(.year, from: .now)
        if profile.lastInvoiceYear != year {
            profile.lastInvoiceYear = year
            profile.nextInvoiceNumber = 1
        }

        let next = profile.nextInvoiceNumber
        let prefix = profile.invoicePrefix.isEmpty ? "SI" : profile.invoicePrefix

        invoice.invoiceNumber = "\(prefix)-\(year)-\(String(format: "%04d", next))"
        profile.nextInvoiceNumber += 1

        invoice.documentType = "invoice"
        invoice.issueDate = .now

        do {
            _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )
            try modelContext.save()
        } catch {
            exportError = error.localizedDescription
            
            Task {
                do {
                    try modelContext.save()
                    Task { await indexInvoiceIfPossible() }   // ✅ success path
                } catch {
                    exportError = error.localizedDescription
                }
            }
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
                forceSaveNow()
                Task { await indexInvoiceIfPossible() }
                dismiss()
            } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")

            // ✅ Open Job workspace folder
            Button { openJobWorkspaceFolder() } label: { Image(systemName: "folder") }

            Button { previewPDF() } label: { Image(systemName: "doc.richtext") }

            Menu {
                Button {
                    Task { @MainActor in
                        uploadingPortalPDF = true
                        portalPDFNotice = nil
                        do {
                            let snapshot = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                                invoice: invoice,
                                profiles: profiles,
                                context: modelContext
                            )
                            let pdfData = InvoicePDFGenerator.makePDFData(invoice: invoice, business: snapshot)
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
            let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)

            // Ensure Files root exists
            try FolderService.bootstrapRootIfNeeded(businessID: biz.id, context: modelContext)
            guard let root = try FolderService.fetchRootFolder(businessID: biz.id, context: modelContext) else {
                workspaceError = "Files root folder could not be loaded."
                return
            }

            // Deterministic job folder name
            let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.isEmpty ? "Project" : title
            let shortID = job.id.uuidString.prefix(8)
            let jobFolderName = "JOB-\(shortID) \(displayTitle)"

            // Find or create job folder under root
            let jobFolder: Folder
            if let existing = allFolders.first(where: { f in
                f.businessID == biz.id && f.parentFolderID == root.id && f.name == jobFolderName
            }) {
                jobFolder = existing
            } else {
                jobFolder = createJobWorkspaceFolder(businessID: biz.id, root: root, jobFolderName: jobFolderName)
            }

            // ✅ Now open the "Invoices" subfolder (create if missing)
            let invoicesFolder: Folder
            if let existingInvoices = allFolders.first(where: { f in
                f.businessID == biz.id && f.parentFolderID == jobFolder.id && f.name == "Invoices"
            }) {
                invoicesFolder = existingInvoices
            } else {
                let parentPath = jobFolder.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let rel = parentPath.isEmpty ? "Invoices" : "\(parentPath)/Invoices"
                let created = Folder(
                    businessID: biz.id,
                    name: "Invoices",
                    relativePath: rel,
                    parentFolderID: jobFolder.id
                )
                modelContext.insert(created)
                try? modelContext.save()
                invoicesFolder = created
            }

            workspaceDestination = WorkspaceDestination(business: biz, folder: invoicesFolder)

        } catch {
            workspaceError = error.localizedDescription
        }
    }

    private func createJobWorkspaceFolder(businessID: UUID, root: Folder, jobFolderName: String) -> Folder {
        let rootPath = root.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let jobRel = rootPath.isEmpty ? jobFolderName : "\(rootPath)/\(jobFolderName)"

        let jobFolder = Folder(
            businessID: businessID,
            name: jobFolderName,
            relativePath: jobRel,
            parentFolderID: root.id
        )
        modelContext.insert(jobFolder)

        // Default subfolders
        let subs = ["Contracts", "Invoices", "Media", "Deliverables", "Reference"]
        for sub in subs {
            let subRel = "\(jobRel)/\(sub)"
            let f = Folder(
                businessID: businessID,
                name: sub,
                relativePath: subRel,
                parentFolderID: jobFolder.id
            )
            modelContext.insert(f)
        }

        try? modelContext.save()
        return jobFolder
    }

    // MARK: - Helpers

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
    
    
    
    @MainActor
    private func indexInvoiceIfPossible() async {
        guard invoice.documentType == "invoice" else { return }
        guard let client = invoice.client else { return }
        guard client.portalEnabled else { return }

        // Require a “real” invoice number as the finalize signal
        let num = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !num.isEmpty else { return }

        do {
            try await PortalBackend.shared.indexInvoiceForDirectory(invoice: invoice, client: client)
        } catch {
            print("Index invoice failed:", error)
        }
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
                context: modelContext
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

    private func saveInvoicePDFToJobFiles(shareAfter: [Any]? = nil) {
        exportError = nil

        guard let job = invoice.job else {
            exportError = "Link this invoice to a Job to save it into Job → Invoices."
            return
        }

        do {
            let pdfData = InvoicePDFService.makePDFData(
                invoice: invoice,
                profiles: profiles,
                context: modelContext
            )

            let invoicesFolder = try JobExportToFilesService.resolveJobSubfolder(
                job: job,
                named: "Invoices",
                context: modelContext
            )

            let prefix = (invoice.documentType == "estimate") ? "Estimate" : "Invoice"
            let fileName = "\(prefix)-\(invoice.invoiceNumber).pdf"

            // check conflict in that folder
            let existing = allFileItems.first(where: {
                $0.folderKey == invoicesFolder.id.uuidString && $0.originalFileName == fileName
            })

            if existing != nil {
                pendingInvoicePDFSave = PendingPDFSave(
                    pdfData: pdfData,
                    fileName: fileName,
                    folder: invoicesFolder,
                    existing: existing,
                    shareAfterSave: shareAfter
                )
                showInvoicePDFConflictDialog = true
            } else {
                _ = try JobExportToFilesService.savePDF(
                    data: pdfData,
                    preferredFileNameWithExtension: fileName,
                    into: invoicesFolder,
                    existingMatch: nil,
                    conflictAction: nil,
                    context: modelContext
                )
                if let shareAfter { shareItems = shareAfter }
            }

        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Share actions

    private func shareFromPreview(url: URL) {
        var items: [Any] = [url]
        items.append(contentsOf: attachmentURLsForInvoice())
        shareItems = items
    }

    private func sharePDFOnly() {
        do {
            let url = try makeInvoicePDFTempURL(suffix: "pdf")
            // Save to Job → Invoices first (then share)
            saveInvoicePDFToJobFiles(shareAfter: [url])
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

    private func sharePDFWithAttachments() {
        do {
            let pdfURL = try makeInvoicePDFTempURL(suffix: "package")
            var items: [Any] = [pdfURL]
            items.append(contentsOf: attachmentURLsForInvoice())
            shareItems = items
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func shareZIPPackage() {
        do {
            let pdfURL = try makeInvoicePDFTempURL(suffix: "package")
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
            context: modelContext
        )
        let prefix = (invoice.documentType == "estimate") ? "Estimate" : "Invoice"
        let filename = "\(prefix)-\(invoice.invoiceNumber)-\(suffix)-\(Date().timeIntervalSince1970)"
        return try InvoicePDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
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

    private var invoiceFolderKey: String {
        "invoice:\(String(describing: invoice.id))"
    }

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

                let fileId = UUID()
                let ext = url.pathExtension.lowercased()
                let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

                let (rel, size) = try AppFileStore.importFile(from: url, fileId: fileId)

                let item = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: invoiceFolderKey,
                    folder: nil
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
            let fileId = UUID()

            let (rel, size) = try AppFileStore.importData(
                data,
                fileId: fileId,
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
                folderKey: invoiceFolderKey,
                folder: nil
            )
            modelContext.insert(file)

            let link = InvoiceAttachment(invoice: invoice, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
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
