//
//  EstimateListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct EstimateListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: \Invoice.issueDate, order: .reverse)
    private var invoices: [Invoice]

    @Query private var profiles: [BusinessProfile]

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

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                // MARK: - Filter Toggle
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Content
                if filteredEstimates.isEmpty {
                    ContentUnavailableView(
                        "No Estimates",
                        systemImage: "doc.text",
                        description: Text("Try changing the filter or create a new estimate.")
                    )
                } else {
                    ForEach(filteredEstimates) { estimate in
                        Button {
                            selectedEstimate = estimate
                        } label: {
                            row(estimate)
                        }
                        .buttonStyle(.plain)
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
                await refreshFilteredEstimatesFromPortal()
                EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            }
        }
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search estimates"
        )

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
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // reset draft fields each time
                    draftName = ""
                    draftClient = nil
                    showingCreateEstimate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }

        // Navigate to created estimate (template-style navigation)
        .navigationDestination(item: $navigateToEstimate) { estimate in
            InvoiceDetailView(invoice: estimate)
        }
        .navigationDestination(item: $selectedEstimate) { estimate in
            InvoiceDetailView(invoice: estimate)
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
        .task {
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            await refreshFilteredEstimatesFromPortal()
        }
    }

    // MARK: - Data (scoped + filtered)

    private var scopedInvoices: [Invoice] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
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

        return SBWNavigationRow(
            title: "Estimate \(estimate.invoiceNumber)",
            subtitle: subtitle
        )
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
    private func refreshFilteredEstimatesFromPortal() async {
        for estimate in filteredEstimates {
            do {
                let remote = try await PortalBackend.shared.fetchEstimateStatus(
                    businessId: estimate.businessID.uuidString,
                    estimateId: estimate.id.uuidString
                )
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
            guard let bizID = activeBiz.activeBusinessID else {
                print("❌ No active business selected")
                return
            }

            let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            let numberOrName = trimmedName.isEmpty ? generateEstimateNumber() : trimmedName

            let estimate = Invoice(
                businessID: bizID,
                invoiceNumber: numberOrName,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                paymentTerms: "Net 14",
                notes: "",
                thankYou: "",
                termsAndConditions: "",
                taxRate: 0,
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
