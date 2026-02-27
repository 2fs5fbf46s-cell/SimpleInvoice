//
//  EstimateListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct EstimateListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    private let businessID: UUID?

    @Query private var invoices: [Invoice]

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    // Navigate to the estimate we just created
    @State private var navigateToEstimate: Invoice? = nil
    @State private var selectedEstimate: Invoice? = nil

    // MARK: - Rename
    @State private var renamingEstimate: Invoice? = nil
    @State private var renameText: String = ""

    // Open detail after creation
    @State private var showingNewEstimate = false
    @State private var newEstimate: Invoice? = nil

    // Create sheet fields
    @State private var showingCreateEstimate = false
    @State private var draftName: String = ""
    @State private var draftClient: Client? = nil
    @State private var showingEstimateSettings = false

    // MARK: - Filters
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case sent = "Sent"
        case accepted = "Accepted"
        case declined = "Declined"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var searchText: String = ""
    @State private var isRefreshingFromPortal = false
    @State private var loadGeneration = UUID()
    @State private var refreshTask: Task<Void, Never>? = nil

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
        businessID ?? activeBiz.activeBusinessID
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { f in
                                Button {
                                    filter = f
                                } label: {
                                    Text(f.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(filter == f ? SBWTheme.brandBlue.opacity(0.22) : Color.primary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // MARK: - Content
                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view estimates.")
                    )
                } else if filteredEstimates.isEmpty {
                    ContentUnavailableView(
                        "No Estimates",
                        systemImage: "doc.text",
                        description: Text("Try changing the filter or create a new estimate.")
                    )
                    Button("Create Estimate") {
                        draftName = ""
                        draftClient = nil
                        showingCreateEstimate = true
                    }
                    .buttonStyle(.plain)
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != .all {
                        Button("Clear Filters") {
                            searchText = ""
                            filter = .all
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(filteredEstimates) { estimate in
                        Button {
                            selectedEstimate = estimate
                        } label: {
                            row(estimate)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                            Button {
                                renamingEstimate = estimate
                                renameText = estimate.invoiceNumber
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                modelContext.delete(estimate)
                                do { try modelContext.save() }
                                catch { print("Failed to save deletes: \(error)") }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteEstimates)
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await guardedRefreshFilteredEstimatesFromPortal(generation: loadGeneration)
                EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            }
        }
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.large)

        // MARK: - Toolbar (matches InvoiceListView style)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    NavigationLink {
                        BusinessProfileView()
                    } label: {
                        Label("Business Profile", systemImage: "gearshape")
                    }

                    NavigationLink {
                        CatalogItemListView()
                    } label: {
                        Label("Saved Items", systemImage: "tray")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEstimateSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }

        // Navigate to created estimate (template-style navigation)
        .navigationDestination(item: $navigateToEstimate) { estimate in
            InvoiceOverviewView(invoice: estimate)
        }
        .navigationDestination(item: $selectedEstimate) { estimate in
            InvoiceOverviewView(invoice: estimate)
        }

        // MARK: - Rename Alert
        .alert("Rename Estimate", isPresented: Binding(
            get: { renamingEstimate != nil },
            set: { if !$0 { renamingEstimate = nil } }
        )) {
            TextField("Name", text: $renameText)

            Button("Save") {
                guard let est = renamingEstimate else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                est.invoiceNumber = trimmed

                do { try modelContext.save() }
                catch { print("Failed to save rename: \(error)") }
                Haptics.success()

                renamingEstimate = nil
            }

            Button("Cancel", role: .cancel) {
                renamingEstimate = nil
            }
        } message: {
            Text("This changes the estimate label shown in the list.")
        }

        // MARK: - Create sheet (name + client)
        .sheet(isPresented: $showingCreateEstimate) {
            NewEstimateSheet(
                name: $draftName,
                client: $draftClient,
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
        .task(id: effectiveBusinessID) {
            loadGeneration = UUID()
            refreshTask?.cancel()
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            let generation = loadGeneration
            refreshTask = Task {
                await guardedRefreshFilteredEstimatesFromPortal(generation: generation)
            }
            await refreshTask?.value
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Data (scoped + filtered)

    private var scopedInvoices: [Invoice] {
        if let bizID = effectiveBusinessID {
            return invoices.filter { $0.businessID == bizID }
        }
        return []
    }

    @MainActor
    private func guardedRefreshFilteredEstimatesFromPortal(generation: UUID) async {
        guard isRefreshingFromPortal == false else { return }
        isRefreshingFromPortal = true
        defer { isRefreshingFromPortal = false }
        await refreshFilteredEstimatesFromPortal(generation: generation)
    }

    private var filteredEstimates: [Invoice] {
        let estimatesOnly = scopedInvoices.filter { $0.documentType == "estimate" }

        let base: [Invoice]
        switch filter {
        case .all:
            base = estimatesOnly
        case .draft:
            base = estimatesOnly.filter { normalizedStatus($0.estimateStatus) == "draft" }
        case .sent:
            base = estimatesOnly.filter { normalizedStatus($0.estimateStatus) == "sent" }
        case .accepted:
            base = estimatesOnly.filter { normalizedStatus($0.estimateStatus) == "accepted" }
        case .declined:
            base = estimatesOnly.filter { normalizedStatus($0.estimateStatus) == "declined" }
        }

        guard !searchText.isEmpty else { return base }

        return base.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(searchText) ||
            ($0.client?.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Row UI (Option A chip styling)

    private func row(_ estimate: Invoice) -> some View {
        let statusText = estimatePillText(for: estimate)
        let clientName = estimate.client?.name ?? "No Client"
        let date = estimate.issueDate.formatted(date: .abbreviated, time: .omitted)
        let total = estimate.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let subtitle = "\(statusText) • \(clientName) • \(date) • \(total)"

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Estimates"))
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Estimate \(estimate.invoiceNumber)")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    SBWStatusPill(text: statusText)
                }
                Text(subtitle.replacingOccurrences(of: "\(statusText) • ", with: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private func estimatePillText(for estimate: Invoice) -> String {
        switch normalizedStatus(estimate.estimateStatus) {
        case "draft": return "DRAFT"
        case "sent": return "SENT"
        case "accepted": return "ACCEPTED"
        case "declined": return "DECLINED"
        default: return "DRAFT"
        }
    }

    private func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @MainActor
    private func refreshFilteredEstimatesFromPortal(generation: UUID) async {
        for estimate in filteredEstimates {
            if generation != loadGeneration || Task.isCancelled { return }
            do {
                let remote = try await PortalBackend.shared.fetchEstimateStatus(
                    businessId: estimate.businessID.uuidString,
                    estimateId: estimate.id.uuidString
                )
                if generation != loadGeneration || Task.isCancelled { return }
                let local = normalizedStatus(estimate.estimateStatus)
                if local != remote.status {
                    EstimateDecisionSync.setEstimateDecision(
                        estimate: estimate,
                        status: remote.status,
                        decidedAt: remote.decidedAt ?? .now
                    )
                }
            } catch {
                continue
            }
        }
        guard generation == loadGeneration, !Task.isCancelled else { return }
        try? modelContext.save()
    }

    // MARK: - Create

    private func generateEstimateNumber() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return "EST-\(df.string(from: Date()))"
    }

    private func createEstimateFromDraft() {
        do {
            guard let bizID = effectiveBusinessID else {
                print("❌ No active business selected")
                return
            }

            let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            let numberOrName = trimmedName.isEmpty ? generateEstimateNumber() : trimmedName

            let profile = profiles.first(where: { $0.businessID == bizID })
            let business = businesses.first(where: { $0.id == bizID })
            let validityDays = max(1, business?.defaultEstimateValidityDays ?? 14)
            let defaultTaxRate = max(0, NSDecimalNumber(decimal: business?.defaultTaxRate ?? 0).doubleValue)
            let defaultPaymentTermsRaw = profile?.defaultEstimatePaymentTerms.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let defaultPaymentTerms = defaultPaymentTermsRaw.isEmpty
                ? "Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")"
                : defaultPaymentTermsRaw
            let defaultNotes = profile?.defaultEstimateNotes ?? ""
            let defaultThankYou = profile?.defaultEstimateThankYou ?? ""
            let defaultTerms = profile?.defaultEstimateTerms ?? ""

            let estimate = Invoice(
                businessID: bizID,
                invoiceNumber: numberOrName,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: validityDays, to: .now) ?? .now,
                paymentTerms: defaultPaymentTerms,
                notes: defaultNotes,
                thankYou: defaultThankYou,
                termsAndConditions: defaultTerms,
                taxRate: defaultTaxRate,
                discountAmount: 0,
                isPaid: false,
                documentType: "estimate",
                client: draftClient,
                job: nil,
                items: []
            )

            estimate.estimateStatus = "draft"
            estimate.estimateAcceptedAt = nil

            modelContext.insert(estimate)
            try modelContext.save()

            showingCreateEstimate = false
            newEstimate = estimate
            showingNewEstimate = true
        } catch {
            print("Failed to create estimate: \(error)")
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
        let statusNotDraft = normalizedStatus(inv.estimateStatus) != "draft"

        let isEmptyDraft = !(hasClient || hasNotes || hasItems || hasMoney || statusNotDraft)

        if forceDelete || isEmptyDraft {
            modelContext.delete(inv)
            do { try modelContext.save() }
            catch { print("Failed to save cancel delete: \(error)") }
        }

        newEstimate = nil
    }

    // MARK: - Deletes

    private func deleteEstimates(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredEstimates[index])
        }
        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }
}
