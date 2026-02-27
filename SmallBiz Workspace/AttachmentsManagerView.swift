import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum ManagedAttachmentEntity {
    case invoice(Invoice)
    case estimate(Invoice)
    case contract(Contract)
    case job(Job)
    case client(Client)
    case booking(requestID: String, businessID: UUID)

    var entityTypeKey: String {
        switch self {
        case .invoice: return "invoice"
        case .estimate: return "estimate"
        case .contract: return "contract"
        case .job: return "job"
        case .client: return "client"
        case .booking: return "booking"
        }
    }

    var businessID: UUID {
        switch self {
        case .invoice(let invoice): return invoice.businessID
        case .estimate(let estimate): return estimate.businessID
        case .contract(let contract): return contract.businessID
        case .job(let job): return job.businessID
        case .client(let client): return client.businessID
        case .booking(_, let businessID): return businessID
        }
    }

    var entityKey: String {
        switch self {
        case .invoice(let invoice): return invoice.id.uuidString
        case .estimate(let estimate): return estimate.id.uuidString
        case .contract(let contract): return contract.id.uuidString
        case .job(let job): return job.id.uuidString
        case .client(let client): return client.id.uuidString
        case .booking(let requestID, _): return requestID
        }
    }

    var title: String {
        switch self {
        case .invoice: return "Invoice Attachments"
        case .estimate: return "Estimate Attachments"
        case .contract: return "Contract Attachments"
        case .job: return "Job Attachments"
        case .client: return "Client Attachments"
        case .booking: return "Booking Attachments"
        }
    }
}

private enum ManagedRelationRef {
    case invoice(InvoiceAttachment)
    case contract(ContractAttachment)
    case client(ClientAttachment)
    case job(JobAttachment)
    case booking(BookingAttachment)
}

private struct ManagedAttachmentRow: Identifiable {
    let id: UUID
    let file: FileItem
    let createdAt: Date
    let relation: ManagedRelationRef
}

struct AttachmentsManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var invoiceAttachments: [InvoiceAttachment]
    @Query private var contractAttachments: [ContractAttachment]
    @Query private var clientAttachments: [ClientAttachment]
    @Query private var jobAttachments: [JobAttachment]
    @Query private var bookingAttachments: [BookingAttachment]

    @State private var showFileImporter = false
    @State private var previewURL: IdentifiableURL? = nil
    @State private var shareItems: [Any]? = nil
    @State private var renameTarget: FileItem? = nil
    @State private var renameText: String = ""
    @State private var notice: String? = nil

    private let entity: ManagedAttachmentEntity

    init(invoice: Invoice) {
        self.entity = invoice.documentType == "estimate" ? .estimate(invoice) : .invoice(invoice)
    }

    init(contract: Contract) {
        self.entity = .contract(contract)
    }

    init(job: Job) {
        self.entity = .job(job)
    }

    init(client: Client) {
        self.entity = .client(client)
    }

    init(bookingRequestID: String, businessID: UUID) {
        self.entity = .booking(requestID: bookingRequestID, businessID: businessID)
    }

    private var rows: [ManagedAttachmentRow] {
        switch entity {
        case .invoice, .estimate:
            let key = entity.entityKey
            return invoiceAttachments
                .filter { $0.invoiceKey == key }
                .compactMap { relation in
                    guard let file = relation.file else { return nil }
                    return ManagedAttachmentRow(id: relation.id, file: file, createdAt: relation.createdAt, relation: .invoice(relation))
                }
                .sorted { $0.createdAt > $1.createdAt }
        case .contract:
            let key = entity.entityKey
            return contractAttachments
                .filter { $0.contractKey == key }
                .compactMap { relation in
                    guard let file = relation.file else { return nil }
                    return ManagedAttachmentRow(id: relation.id, file: file, createdAt: relation.createdAt, relation: .contract(relation))
                }
                .sorted { $0.createdAt > $1.createdAt }
        case .client:
            let key = entity.entityKey
            return clientAttachments
                .filter { $0.clientKey == key }
                .compactMap { relation in
                    guard let file = relation.file else { return nil }
                    return ManagedAttachmentRow(id: relation.id, file: file, createdAt: relation.createdAt, relation: .client(relation))
                }
                .sorted { $0.createdAt > $1.createdAt }
        case .job:
            let key = entity.entityKey
            return jobAttachments
                .filter { $0.jobKey == key }
                .compactMap { relation in
                    guard let file = relation.file else { return nil }
                    return ManagedAttachmentRow(id: relation.id, file: file, createdAt: relation.createdAt, relation: .job(relation))
                }
                .sorted { $0.createdAt > $1.createdAt }
        case .booking(let requestID, _):
            return bookingAttachments
                .filter { $0.bookingKey == requestID }
                .compactMap { relation in
                    guard let file = relation.file else { return nil }
                    return ManagedAttachmentRow(id: relation.id, file: file, createdAt: relation.createdAt, relation: .booking(relation))
                }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        List {
            SBWCardContainer {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Attachments")
                            .font(.headline)
                        Text("\(rows.count) file\(rows.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            if rows.isEmpty {
                SBWCardContainer {
                    ContentUnavailableView(
                        "No Attachments",
                        systemImage: "paperclip",
                        description: Text("Add files to keep documents with this record.")
                    )
                    Button("Add Attachment") { showFileImporter = true }
                        .buttonStyle(.borderedProminent)
                        .tint(SBWTheme.brandBlue)
                        .padding(.top, 8)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(rows) { row in
                    attachmentRow(row)
                        .listRowBackground(Color.clear)
                        .transition(.opacity)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                renameTarget = row.file
                                renameText = row.file.displayName
                            }
                            .tint(.blue)

                            Button("Share") {
                                shareAttachment(row.file)
                            }
                            .tint(.teal)

                            Button(role: .destructive) {
                                deleteAttachment(row)
                            } label: {
                                Text("Delete")
                            }
                        }
                }
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle(entity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { showFileImporter = true }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: UTType.importable,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importAttachment(from: url)
        }
        .sheet(item: $previewURL) { item in
            NavigationStack {
                QuickLookPreview(url: item.url)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { previewURL = nil }
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
        .alert("Rename Attachment", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("File name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Update the display name shown in summaries.")
        }
    }

    private func attachmentRow(_ row: ManagedAttachmentRow) -> some View {
        Button {
            previewAttachment(row.file)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: row.file))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.file.displayName.isEmpty ? row.file.originalFileName : row.file.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(byteCountString(row.file.byteCount)) • \(dateString(row.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func importAttachment(from sourceURL: URL) {
        do {
            let result = try AttachmentStorage.importFile(
                from: sourceURL,
                businessID: entity.businessID,
                entityType: entity.entityTypeKey,
                entityKey: entity.entityKey
            )
            let file = result.file
            modelContext.insert(file)

            switch entity {
            case .invoice(let invoice), .estimate(let invoice):
                let relation = InvoiceAttachment()
                relation.invoice = invoice
                relation.file = file
                relation.invoiceKey = invoice.id.uuidString
                relation.fileKey = file.id.uuidString
                relation.createdAt = .now
                modelContext.insert(relation)
            case .contract(let contract):
                let relation = ContractAttachment()
                relation.contract = contract
                relation.file = file
                relation.contractKey = contract.id.uuidString
                relation.fileKey = file.id.uuidString
                relation.createdAt = .now
                modelContext.insert(relation)
            case .client(let client):
                let relation = ClientAttachment()
                relation.client = client
                relation.file = file
                relation.clientKey = client.id.uuidString
                relation.fileKey = file.id.uuidString
                relation.createdAt = .now
                modelContext.insert(relation)
            case .job(let job):
                let relation = JobAttachment()
                relation.job = job
                relation.file = file
                relation.jobKey = job.id.uuidString
                relation.fileKey = file.id.uuidString
                relation.createdAt = .now
                modelContext.insert(relation)
            case .booking(let requestID, _):
                let relation = BookingAttachment(bookingKey: requestID, file: file)
                modelContext.insert(relation)
            }

            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.2)) {}
            Haptics.success()
        } catch {
            Haptics.error()
            notice = "Could not add attachment."
            print("Attachment import failed: \(error)")
        }
    }

    private func deleteAttachment(_ row: ManagedAttachmentRow) {
        let file = row.file
        switch row.relation {
        case .invoice(let relation): modelContext.delete(relation)
        case .contract(let relation): modelContext.delete(relation)
        case .client(let relation): modelContext.delete(relation)
        case .job(let relation): modelContext.delete(relation)
        case .booking(let relation): modelContext.delete(relation)
        }

        do {
            try modelContext.save()
            if hasAnyReference(to: file.id.uuidString) == false {
                AttachmentStorage.bestEffortDelete(file)
                modelContext.delete(file)
                try modelContext.save()
            }
            withAnimation(.easeInOut(duration: 0.2)) {}
            Haptics.success()
        } catch {
            Haptics.error()
            notice = "Could not delete attachment."
            print("Attachment delete failed: \(error)")
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target.displayName = trimmed
        do {
            try modelContext.save()
            Haptics.success()
        } catch {
            Haptics.error()
            notice = "Could not rename attachment."
            print("Attachment rename failed: \(error)")
        }
        renameTarget = nil
    }

    private func previewAttachment(_ file: FileItem) {
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            previewURL = IdentifiableURL(url: url)
        } catch {
            notice = "Attachment file is missing."
        }
    }

    private func shareAttachment(_ file: FileItem) {
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            shareItems = [url]
        } catch {
            notice = "Attachment file is missing."
        }
    }

    private func hasAnyReference(to fileKey: String) -> Bool {
        if invoiceAttachments.contains(where: { $0.fileKey == fileKey }) { return true }
        if contractAttachments.contains(where: { $0.fileKey == fileKey }) { return true }
        if clientAttachments.contains(where: { $0.fileKey == fileKey }) { return true }
        if jobAttachments.contains(where: { $0.fileKey == fileKey }) { return true }
        if bookingAttachments.contains(where: { $0.fileKey == fileKey }) { return true }
        return false
    }

    private func iconName(for file: FileItem) -> String {
        let ext = file.fileExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["doc", "docx", "rtf", "txt", "pages"].contains(ext) { return "doc.text" }
        if ["xls", "xlsx", "csv", "numbers"].contains(ext) { return "tablecells" }
        return "paperclip"
    }

    private func byteCountString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
