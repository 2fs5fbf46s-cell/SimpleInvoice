import OSLog
//
//  CreateMenuSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

struct CreateMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query private var profiles: [BusinessProfile]

    // Navigation target created here
    @State private var createdInvoice: Invoice? = nil
    @State private var createdContract: Contract? = nil

    // New Estimate (name + client)
    @State private var showNewEstimateSheet = false
    @State private var draftEstimateName: String = ""
    @State private var draftEstimateClient: Client? = nil

    // New Client
    @State private var newClientDraft: Client? = nil
    @State private var openExistingClient: Client? = nil

    // New Job (Clients-style)
    @State private var showNewJobSheet = false
    @State private var newJobDraft: Job? = nil
    /// The job just saved from the New Job sheet, opened once the sheet is
    /// gone (like a new invoice opens) instead of landing back on this menu.
    @State private var savedJob: Job? = nil
    @State private var createdJob: Job? = nil

    // New Contract
    @State private var showNewContractSheet = false
    @State private var newExpense: Expense? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground).ignoresSafeArea()

                // Subtle header wash
                SBWTheme.brandGradient
                    .opacity(SBWTheme.headerWashOpacity)
                    .blur(radius: SBWTheme.headerWashBlur)
                    .frame(height: SBWTheme.headerWashHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        header

                        CreateSectionCard(title: "Billing") {
                            CreateActionRow(
                                title: "New Invoice",
                                subtitle: "Bill a customer",
                                systemImage: "doc.plaintext",
                                chipFill: SBWTheme.chipFill(for: "Invoices")
                            ) {
                                createInvoiceDraftAndOpen()
                            }

                            Divider().opacity(0.6)

                            CreateActionRow(
                                title: "New Estimate",
                                subtitle: "Send a quote",
                                systemImage: "doc.text.magnifyingglass",
                                chipFill: SBWTheme.chipFill(for: "Estimates")
                            ) {
                                draftEstimateName = ""
                                draftEstimateClient = nil
                                showNewEstimateSheet = true
                            }

                            Divider().opacity(0.6)

                            CreateActionRow(
                                title: "New Contract",
                                subtitle: "Start an agreement",
                                systemImage: "doc.text",
                                chipFill: SBWTheme.chipFill(for: "Contracts")
                            ) {
                                showNewContractSheet = true
                            }

                            Divider().opacity(0.6)

                            CreateActionRow(
                                title: "New Expense",
                                subtitle: "Log money you spent",
                                systemImage: "creditcard",
                                chipFill: SBWTheme.chipFill(for: "Expenses")
                            ) {
                                startExpense()
                            }
                        }

                        CreateSectionCard(title: "Customers & Requests") {
                            CreateActionRow(
                                title: "New Client",
                                subtitle: "Add a customer",
                                systemImage: "person.badge.plus",
                                chipFill: SBWTheme.chipFill(for: "Customers")
                            ) {
                                addClientAndOpenSheet()
                            }

                            Divider().opacity(0.6)

                            CreateActionRow(
                                title: "New Job",
                                subtitle: "Track work for a client",
                                systemImage: "tray.full",
                                chipFill: SBWTheme.chipFill(for: "Requests")
                            ) {
                                addJobAndOpenSheet()
                            }
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .sbwNavigationBarBackdrop()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        hapticTap()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(SBWTheme.cardStroke, lineWidth: 1)
                            )
                    }
                }
            }
            // Navigate into invoice/estimate editor after creating the record
            .navigationDestination(item: $createdInvoice) { inv in
                InvoiceDetailView(invoice: inv)
            }
            .onChange(of: createdInvoice) { old, new in
                if new == nil, let old { discardIfUntouched(old) }
            }
            .navigationDestination(item: $createdJob) { job in
                JobDetailView(job: job)
            }
            .navigationDestination(item: $createdContract) { contract in
                ContractDetailView(contract: contract)
            }
            .navigationDestination(item: $openExistingClient) { client in
                ClientDetailView(client: client)
            }

            // New estimate: name + client sheet
            .sheet(isPresented: $showNewEstimateSheet) {
                NewEstimateSheet(
                    name: $draftEstimateName,
                    client: $draftEstimateClient,
                    businessID: activeBiz.activeBusinessID,
                    onCancel: { showNewEstimateSheet = false },
                    onCreate: { createEstimateFromDraftAndOpen() }
                )
            }

            .sheet(isPresented: $showNewContractSheet) {
                NavigationStack {
                CreateContractStartView(
                        businessID: activeBiz.activeBusinessID,
                        onCreated: { contract in
                            createdContract = contract
                            showNewContractSheet = false
                        },
                        onCancel: {
                            showNewContractSheet = false
                        }
                    )
                }
            }

            // New client: the same sheet the estimate and invoice forms use,
            // then open the client so the next step is right there.
            .sheet(item: $newClientDraft) { draft in
                NewClientSheet(draft: draft) { saved in
                    newClientDraft = nil
                    if let saved {
                        DispatchQueue.main.async { openExistingClient = saved }
                    }
                }
            }

            .sheet(item: $newExpense) { expense in
                NavigationStack {
                    ExpenseFormView(expense: expense, isDraft: true) {
                        newExpense = nil
                        dismiss()
                    } onCancel: {
                        if expense.amountCents <= 0 {
                            modelContext.delete(expense)
                            try? modelContext.save()
                        }
                        newExpense = nil
                    }
                }
            }

            // New job flow (uses JobDetailView)
            .sheet(isPresented: $showNewJobSheet, onDismiss: {
                newJobDraft = nil
                createdJob = savedJob
                savedJob = nil
            }) {
                NavigationStack {
                    if let newJobDraft {
                        JobDetailView(job: newJobDraft, isDraft: true)
                            .navigationTitle("New Job")
                            .navigationBarTitleDisplayMode(.inline)
                            .sbwNavigationBarBackdrop()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { deleteJobIfEmptyAndClose() }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        if newJobDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            deleteJobIfEmptyAndClose()
                                            return
                                        }
                                        do {
                                            modelContext.insert(newJobDraft)
                                            try modelContext.save()
                                            _ = try WorkspaceProvisioningService.ensureJobWorkspace(job: newJobDraft, context: modelContext)
                                            savedJob = newJobDraft
                                            showNewJobSheet = false
                                        }
                                        catch { SBWLog.ui.problem("Failed to save new job: \(error)") }
                                    }
                                }
                            }
                    } else {
                        ProgressView("Loading…").navigationTitle("New Job")
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("What are we creating?")
                    .font(.scaledSystem(size: 22, weight: .bold, relativeTo: .title2))
                Text("Pick a starting point — you can refine details after.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.bottom, 2)
    }

    // MARK: - Profile defaults (scoped)

    private func startExpense() {
        guard let businessID = activeBiz.activeBusinessID else { return }
        let expense = Expense(businessID: businessID, date: .now)
        modelContext.insert(expense)
        try? modelContext.save()
        newExpense = expense
    }

    private func getOrCreateProfileForActiveBusiness() -> BusinessProfile? {
        guard let bizID = activeBiz.activeBusinessID else { return nil }

        if let existing = profiles.first(where: { $0.businessID == bizID }) {
            return existing
        }

        let created = BusinessProfile(businessID: bizID)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private func preloadDefaults(into invoice: Invoice) {
        guard let p = getOrCreateProfileForActiveBusiness() else { return }

        if invoice.thankYou.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invoice.thankYou = p.defaultThankYou
        }
        if invoice.termsAndConditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invoice.termsAndConditions = p.defaultTerms
        }
    }

    // MARK: - Create Invoice / Estimate

    private func createInvoiceDraftAndOpen() {
        guard let bizID = activeBiz.activeBusinessID else {
            SBWLog.ui.problem("❌ No active business selected"); return
        }

        let inv = Invoice(
            businessID: bizID,
            invoiceNumber: getOrCreateProfileForActiveBusiness().map { InvoiceNumberGenerator.generateNextNumber(profile: $0) } ?? "",
            documentType: "invoice",
            items: []
        )

        preloadDefaults(into: inv)

        modelContext.insert(inv)
        try? modelContext.save()

        createdInvoice = inv
    }

    /// Backing out of a new invoice without choosing a client or adding a
    /// line left an empty draft behind, holding a number. Remove it and give
    /// the number back.
    private func discardIfUntouched(_ invoice: Invoice) {
        guard invoice.documentType == "invoice",
              invoice.client == nil,
              invoice.job == nil,
              (invoice.items ?? []).isEmpty,
              (invoice.payments ?? []).isEmpty,
              !invoice.wasSent
        else { return }
        let context = modelContext
        let profile = profiles.first { $0.businessID == invoice.businessID }
        // After the pop finishes: deleting a model its screen still shows
        // crashes SwiftData views.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let profile { InvoiceNumberGenerator.release(invoice.trimmedInvoiceNumber, profile: profile) }
            context.delete(invoice)
            try? context.save()
        }
    }

    private func createEstimateFromDraftAndOpen() {
        guard let bizID = activeBiz.activeBusinessID else {
            SBWLog.ui.problem("❌ No active business selected"); return
        }

        let est: Invoice
        do {
            est = try EstimateDrafts.make(
                name: draftEstimateName,
                client: draftEstimateClient,
                businessID: bizID,
                context: modelContext
            )
        } catch {
            SBWLog.ui.problem("Failed to create estimate: \(error)")
            return
        }

        showNewEstimateSheet = false
        createdInvoice = est
    }

    // MARK: - New Client

    private func addClientAndOpenSheet() {
        guard let bizID = activeBiz.activeBusinessID else {
            SBWLog.ui.problem("❌ No active business selected"); return
        }
        newClientDraft = NewClientSheet.makeDraft(businessID: bizID, in: modelContext)
    }

    // MARK: - New Job (match JobsListView Clients-style)

    private func addJobAndOpenSheet() {
        guard let bizID = activeBiz.activeBusinessID else {
            SBWLog.ui.problem("❌ No active business selected"); return
        }

        let job = Job(
            businessID: bizID,
            // The same rounded start the Jobs list uses, not this minute.
            startDate: JobDetailView.defaultScheduleStart(),
            endDate: JobDetailView.defaultScheduleStart().addingTimeInterval(2 * 3600)
        )
        job.title = ""
        job.status = "scheduled"

        newJobDraft = job
        showNewJobSheet = true
    }

    private func deleteJobIfEmptyAndClose() {
        newJobDraft = nil
        showNewJobSheet = false
    }

    // MARK: - Draft numbers

}
private func hapticTap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}


// MARK: - UI Components

struct CreateSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)


            VStack(spacing: 0) {
                content
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 6)

        }
    }
}

struct CreateActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let chipFill: AnyShapeStyle
    let action: () -> Void

    init(title: String, subtitle: String, systemImage: String, chipFill: AnyShapeStyle, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.chipFill = chipFill
        self.action = action
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(chipFill)

                    Image(systemName: systemImage)
                        .font(.scaledSystem(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.scaledSystem(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.scaledSystem(size: 13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.scaledSystem(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8) // slightly roomier tap target
        }
        .buttonStyle(SBWPressableRowStyle())
    }
    private struct SBWPressableRowStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.92 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

}
