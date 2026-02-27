import SwiftUI
import SwiftData

private enum ContractSummarySection: Hashable {
    case overviewBody
    case signatures
    case attachments
    case activity
    case advanced
}

private enum ContractSummarySheet: String, Identifiable {
    case editor
    case body
    case attachments
    case activity
    case previewPDF

    var id: String { rawValue }
}

private struct ContractSummaryPDFItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContractSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var contract: Contract

    @Query private var profiles: [BusinessProfile]
    @Query private var attachments: [ContractAttachment]

    @State private var expandedSection: ContractSummarySection? = nil
    @State private var activeSheet: ContractSummarySheet? = nil
    @State private var shareItems: [Any]? = nil
    @State private var exportError: String? = nil
    @State private var portalError: String? = nil
    @State private var portalNotice: String? = nil
    @State private var previewItem: ContractSummaryPDFItem? = nil

    init(contract: Contract) {
        self.contract = contract
        let key = contract.id.uuidString
        self._attachments = Query(
            filter: #Predicate<ContractAttachment> { a in
                a.contractKey == key
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var navTitle: String {
        let t = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Contract" : t
    }

    private var statusText: String {
        switch contract.status {
        case .draft:
            return "DRAFT"
        case .sent:
            return "SENT"
        case .signed:
            return "SIGNED"
        case .cancelled:
            return "EXPIRED"
        }
    }

    private var clientText: String {
        if let name = contract.resolvedClient?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "No Client"
    }

    private var lastUpdated: Date {
        contract.updatedAt > contract.createdAt ? contract.updatedAt : contract.createdAt
    }

    private var signaturesSorted: [ContractSignature] {
        (contract.signatures ?? []).sorted { $0.signedAt > $1.signedAt }
    }

    private var hasSignedPDF: Bool {
        !contract.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: navTitle,
                    subtitle: "Contract Summary",
                    status: statusText
                )
                SummaryKit.SummaryKeyValueRow(label: "Client", value: clientText)
                SummaryKit.SummaryKeyValueRow(
                    label: "Updated",
                    value: lastUpdated.formatted(date: .abbreviated, time: .shortened)
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Created",
                    value: contract.createdAt.formatted(date: .abbreviated, time: .omitted)
                )
                if let signedAt = contract.signedAt {
                    SummaryKit.SummaryKeyValueRow(
                        label: "Signed",
                        value: signedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                SummaryKit.PrimaryActionRow(actions: [
                    .init(title: "Send", systemImage: "paperplane") {
                        sendContractAction()
                    },
                    .init(title: "Share Portal", systemImage: "rectangle.portrait.and.arrow.right") {
                        sharePortalAction()
                    },
                    .init(title: "View / Edit", systemImage: "square.and.pencil") {
                        activeSheet = .editor
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
                title: "Contract Body / Terms",
                subtitle: "Preview and full view",
                icon: "doc.text",
                isExpanded: expandedSection == .overviewBody,
                onToggle: { toggle(.overviewBody) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    let body = contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(body.isEmpty ? "No contract body." : String(body.prefix(300)))
                        .font(.subheadline)
                        .foregroundStyle(body.isEmpty ? .secondary : .primary)
                        .lineLimit(6)
                    Button("View Full") {
                        activeSheet = .body
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Signatures",
                subtitle: "Signer and signed PDF",
                icon: "signature",
                isExpanded: expandedSection == .signatures,
                onToggle: { toggle(.signatures) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if signaturesSorted.isEmpty {
                        Text("No signatures yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(signaturesSorted.prefix(3)) { sig in
                            SummaryKit.SummaryKeyValueRow(
                                label: sig.signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Signer" : sig.signerName,
                                value: sig.signedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }

                    if hasSignedPDF {
                        Button("View Signed PDF") {
                            openSignedPDF()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Attachments",
                subtitle: "\(attachments.count) files",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: { toggle(.attachments) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if attachments.isEmpty {
                        Text("No attachments")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments.prefix(3)) { attachment in
                            HStack(spacing: 8) {
                                Image(systemName: attachmentIconName(for: attachment.file))
                                    .foregroundStyle(.secondary)
                                Text(attachment.file?.displayName ?? "File")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Button("Manage Attachments") {
                        activeSheet = .attachments
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Activity / Timeline",
                subtitle: "Recent contract events",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .activity,
                onToggle: { toggle(.activity) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activityEntries.prefix(5), id: \.title) { entry in
                        SummaryKit.SummaryKeyValueRow(label: entry.title, value: entry.detail)
                    }
                    Button("View Full Activity") {
                        activeSheet = .activity
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Advanced",
                subtitle: "Rare actions and IDs",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: { toggle(.advanced) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Contract ID", value: contract.id.uuidString)
                    SummaryKit.SummaryKeyValueRow(label: "Portal", value: contractPortalSyncStatusText)
                    if let message = contract.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Open Full Editor") {
                        activeSheet = .editor
                    }
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
        .navigationTitle("Contract Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .editor:
                    ContractDetailView(contract: contract)
                case .body:
                    ContractBodyView(contract: contract)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeSheet = nil }
                            }
                        }
                case .activity:
                    ContractActivityView(contract: contract)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeSheet = nil }
                            }
                        }
                case .attachments:
                    AttachmentsManagerView(contract: contract)
                case .previewPDF:
                    if let previewItem {
                        PDFPreviewView(url: previewItem.url)
                            .navigationTitle("Signed PDF")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { activeSheet = nil }
                                }
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
        .alert("Contract", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Client Portal", isPresented: Binding(
            get: { portalError != nil },
            set: { if !$0 { portalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(portalError ?? "")
        }
    }

    private func attachmentIconName(for file: FileItem?) -> String {
        guard let ext = file?.fileExtension.lowercased() else { return "paperclip" }
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["doc", "docx", "rtf", "txt", "pages"].contains(ext) { return "doc.text" }
        return "paperclip"
    }

    private func toggle(_ section: ContractSummarySection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
    }

    private var activityEntries: [(title: String, detail: String)] {
        var rows: [(String, String)] = [
            ("Created", contract.createdAt.formatted(date: .abbreviated, time: .omitted)),
            ("Updated", contract.updatedAt.formatted(date: .abbreviated, time: .shortened)),
            ("Status", statusText)
        ]

        if let signedAt = contract.signedAt {
            rows.append(("Signed", signedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        if contract.portalNeedsUpload {
            rows.append(("Portal", "Pending upload"))
        }
        if let err = contract.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
            rows.append(("Portal Error", err))
        }
        return rows
    }

    private var contractPortalSyncStatusText: String {
        if !PortalAutoSyncService.isEligible(contract: contract) {
            return "Not eligible"
        }
        if contract.portalUploadInFlight {
            return "Uploading"
        }
        if let message = contract.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return "Upload failed"
        }
        if contract.portalNeedsUpload {
            return "Pending upload"
        }
        return "Up to date"
    }

    private func sendContractAction() {
        if contract.status == .draft {
            contract.status = .sent
        }
        contract.updatedAt = .now
        try? modelContext.save()

        do {
            let url = try persistContractPDFToJobFiles()
            shareItems = [url]
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func sharePortalAction() {
        Task {
            do {
                if contract.client == nil, let resolved = contract.resolvedClient {
                    contract.client = resolved
                    try? modelContext.save()
                }
                let token = try await PortalBackend.shared.createContractPortalToken(contract: contract)
                let url = PortalBackend.shared.portalContractURL(contractId: contract.id.uuidString, token: token)
                shareItems = [url]
                showNotice("Sharing portal link…")
            } catch {
                portalError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func showNotice(_ text: String) {
        portalNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if portalNotice == text {
                portalNotice = nil
            }
        }
    }

    private func persistContractPDFToJobFiles() throws -> URL {
        try DocumentFileIndexService.persistContractPDF(
            contract: contract,
            business: profiles.first,
            context: modelContext
        )
    }

    private func openSignedPDF() {
        do {
            let relative = contract.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relative.isEmpty else {
                exportError = "Signed PDF not available yet."
                return
            }
            let url = try AppFileStore.absoluteURL(forRelativePath: relative)
            previewItem = ContractSummaryPDFItem(url: url)
            activeSheet = .previewPDF
        } catch {
            exportError = error.localizedDescription
        }
    }
}
