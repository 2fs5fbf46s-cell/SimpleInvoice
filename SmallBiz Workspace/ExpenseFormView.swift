import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Add/edit form for a single expense. Used two ways: pushed for an existing
/// expense (auto-saves as you type, like `ClientEditView`), or presented in a
/// sheet for a freshly-inserted draft with explicit Save/Cancel — the same
/// "insert now, delete if abandoned" shape `JobListView` uses for a new job.
struct ExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var expense: Expense
    let isDraft: Bool
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Query private var clients: [Client]
    @Query private var jobs: [Job]
    @Query private var attachments: [ExpenseAttachment]

    @State private var showPhotosSheet = false
    @State private var attachError: String? = nil
    @State private var previewItem: IdentifiableURL? = nil

    init(
        expense: Expense,
        isDraft: Bool,
        onSave: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.expense = expense
        self.isDraft = isDraft
        self.onSave = onSave
        self.onCancel = onCancel

        let businessID = expense.businessID
        _clients = Query(
            filter: #Predicate<Client> { $0.businessID == businessID },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
        _jobs = Query(
            filter: #Predicate<Job> { $0.businessID == businessID },
            sort: [SortDescriptor(\Job.startDate, order: .reverse)]
        )

        let key = expense.id.uuidString
        _attachments = Query(
            filter: #Predicate<ExpenseAttachment> { $0.expenseKey == key },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var isValid: Bool {
        expense.amountCents > 0
    }

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", value: $expense.amountDollars, format: .number)
                        .keyboardType(.decimalPad)
                        .onChange(of: expense.amountDollars) { _, _ in saveIfEditing() }
                }

                Picker("Category", selection: $expense.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .onChange(of: expense.category) { _, _ in saveIfEditing() }
            }

            Section("Details") {
                TextField("Vendor", text: $expense.vendor)
                    .onChange(of: expense.vendor) { _, _ in saveIfEditing() }

                DatePicker("Date", selection: $expense.date, displayedComponents: .date)
                    .onChange(of: expense.date) { _, _ in saveIfEditing() }

                Toggle("Tax Deductible", isOn: $expense.isTaxDeductible)
                    .onChange(of: expense.isTaxDeductible) { _, _ in saveIfEditing() }
            }

            Section("Link to (Optional)") {
                Picker("Client", selection: Binding<UUID?>(
                    get: { expense.clientID },
                    set: { expense.clientID = $0; saveIfEditing() }
                )) {
                    Text("No Client").tag(nil as UUID?)
                    ForEach(clients) { client in
                        Text(client.name.isEmpty ? "Client" : client.name)
                            .tag(Optional(client.id))
                    }
                }

                Picker("Job", selection: Binding<UUID?>(
                    get: { expense.jobID },
                    set: { expense.jobID = $0; saveIfEditing() }
                )) {
                    Text("No Job").tag(nil as UUID?)
                    ForEach(jobs) { job in
                        Text(job.title.isEmpty ? "Job" : job.title)
                            .tag(Optional(job.id))
                    }
                }
            }

            Section("Notes") {
                TextField("Notes (optional)", text: $expense.notes, axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: expense.notes) { _, _ in saveIfEditing() }
            }

            Section("Receipt") {
                if attachments.isEmpty {
                    Text("No receipt photo yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { attachment in
                        Button {
                            openPreview(attachment)
                        } label: {
                            HStack {
                                Text(attachment.file?.displayName ?? "Receipt")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: removeAttachments)
                }

                Button {
                    showPhotosSheet = true
                } label: {
                    Label("Attach Receipt Photo", systemImage: "camera")
                }
                .disabled(isDraft && !isValid)
            }
        }
        .navigationTitle(isDraft ? "New Expense" : "Expense")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            if isDraft {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try modelContext.save()
                            Haptics.success()
                            onSave?()
                        } catch {
                            Haptics.error()
                            SBWLog.ui.problem("Failed to save new expense: \(error)")
                        }
                    }
                    .disabled(!isValid)
                }
            } else {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        modelContext.delete(expense)
                        do { try modelContext.save() } catch {
                            SBWLog.ui.problem("Failed to save after deleting expense: \(error)")
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotosSheet) {
            NavigationStack {
                List {
                    PhotosImportButton { data, suggestedName in
                        importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                        showPhotosSheet = false
                    }
                }
                .navigationTitle("Import Receipt")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showPhotosSheet = false }
                    }
                }
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .alert("Attachment Error", isPresented: Binding(
            get: { attachError != nil },
            set: { if !$0 { attachError = nil } }
        )) {
            Button("OK", role: .cancel) { attachError = nil }
        } message: {
            Text(attachError ?? "")
        }
    }

    private func saveIfEditing() {
        guard !isDraft else { return }
        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save expense edit: \(error)") }
    }

    // MARK: - Receipt attachment

    private func importAndAttachFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let business = try fetchBusiness(for: expense.businessID)
            let folder = try WorkspaceProvisioningService.resolveFolder(
                business: business,
                client: nil,
                job: nil,
                kind: .photos,
                context: modelContext
            )

            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: folder.relativePath,
                preferredFileName: suggestedFileName
            )

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = "public.jpeg"

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

            let link = ExpenseAttachment(expense: expense, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func removeAttachments(at offsets: IndexSet) {
        let toDelete: [ExpenseAttachment] = offsets.compactMap { idx -> ExpenseAttachment? in
            guard idx < attachments.count else { return nil }
            return attachments[idx]
        }
        for attachment in toDelete {
            modelContext.delete(attachment)
        }
        do { try modelContext.save() } catch {
            attachError = error.localizedDescription
        }
    }

    private func openPreview(_ attachment: ExpenseAttachment) {
        guard let file = attachment.file else {
            attachError = "This attachment's file record is missing."
            return
        }
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                attachError = "This file is missing from local storage."
                return
            }
            previewItem = IdentifiableURL(url: url)
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func fetchBusiness(for businessID: UUID) throws -> Business {
        if let match = try modelContext.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first {
            return match
        }
        return try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)
    }
}
