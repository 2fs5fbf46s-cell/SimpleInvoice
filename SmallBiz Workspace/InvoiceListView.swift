//
//  InvoiceListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct InvoiceListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: \Invoice.issueDate, order: .reverse)
    private var invoices: [Invoice]

    @Query private var profiles: [BusinessProfile]

    @State private var showingNewInvoice = false
    @State private var showingTemplates = false
    @State private var showingInvoiceSettings = false

    // Navigate to the invoice created from a template
    @State private var navigateToInvoice: Invoice? = nil
    @State private var selectedInvoice: Invoice? = nil

    // MARK: - Filters
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case sent = "Sent"
        case paid = "Paid"
        case overdue = "Overdue"

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
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search invoices", text: $searchText)
                            .textInputAutocapitalization(.never)

                        Button {
                            showingNewInvoice = true
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
                if activeBiz.activeBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view invoices.")
                    )
                } else if filteredInvoices.isEmpty {
                    ContentUnavailableView(
                        "No Invoices",
                        systemImage: "doc.text",
                        description: Text("Try changing the filter or create a new invoice.")
                    )
                } else {
                    ForEach(filteredInvoices) { invoice in
                        Button {
                            selectedInvoice = invoice
                        } label: {
                            row(invoice)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteInvoices)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.large)
        

        // MARK: - Toolbar
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

                    Button { showingTemplates = true } label: {
                        Label("Templates", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingInvoiceSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }

        }

        // MARK: - Sheets
        .sheet(isPresented: $showingNewInvoice) {
            NewInvoiceView()
        }
        .sheet(isPresented: $showingTemplates) {
            NavigationStack {
                InvoiceTemplatePickerView(
                    templates: builtInTemplates(),
                    onUse: { template in
                        createInvoiceFromTemplate(template)
                    }
                )
                .navigationTitle("Templates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingTemplates = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingInvoiceSettings) {
            NavigationStack {
                InvoiceSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingInvoiceSettings = false }
                        }
                    }
            }
        }

        // Navigate to created invoice after template selection
        .navigationDestination(item: $navigateToInvoice) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
        .navigationDestination(item: $selectedInvoice) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
    }


    // MARK: - Filtered data (✅ excludes estimates)

    private var filteredInvoices: [Invoice] {
        let nonEstimates = scopedInvoices.filter { $0.documentType != "estimate" }

        let base: [Invoice]
        switch filter {
        case .all:
            base = nonEstimates
        case .draft:
            base = nonEstimates.filter { !($0.isPaid) && ($0.items ?? []).isEmpty }
        case .sent:
            base = nonEstimates.filter { !($0.isPaid) && !($0.dueDate < Date()) && !($0.items ?? []).isEmpty }
        case .paid:
            base = nonEstimates.filter { $0.isPaid }
        case .overdue:
            base = nonEstimates.filter { !$0.isPaid && $0.dueDate < Date() }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }

        return base.filter { invoice in
            if invoice.invoiceNumber.localizedCaseInsensitiveContains(q) { return true }
            if (invoice.client?.name ?? "").localizedCaseInsensitiveContains(q) { return true }
            if (invoice.notes).localizedCaseInsensitiveContains(q) { return true }
            if (invoice.sourceBookingRequestId ?? "").localizedCaseInsensitiveContains(q) { return true }

            // Convenience: allow searching "final" to find booking-created final drafts
            if q.lowercased().contains("final"), isFinalDraft(invoice) { return true }

            return false
        }
    }

    private var scopedInvoices: [Invoice] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
    }

    private func isFinalDraft(_ invoice: Invoice) -> Bool {
        // We create these from booking approval; they are normal-numbered invoices.
        // Detection is based on linkage + the note prefix we add.
        let hasBookingLink = (invoice.sourceBookingRequestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let notes = (invoice.notes).lowercased()
        let isFinalNote = notes.contains("final invoice draft created")
        return hasBookingLink && isFinalNote
    }

    // MARK: - Row UI (Option A polish: icon chip + content)

    private func row(_ invoice: Invoice) -> some View {
        let statusText = invoice.isPaid ? "PAID" : "UNPAID"
        let clientName = invoice.client?.name ?? "No Client"
        let date = invoice.issueDate.formatted(date: .abbreviated, time: .omitted)
        let total = invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let finalBadge = isFinalDraft(invoice) ? "FINAL • " : ""
        let subtitle = "\(finalBadge)\(statusText) • \(clientName) • \(date) • \(total)"

        return HStack(alignment: .top, spacing: 12) {

            // Leading icon chip (matches Dashboard/Jobs/Estimates)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Invoices"))
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                let isFinal = isFinalDraft(invoice)
                HStack {
                    Text(invoice.invoiceNumber.isEmpty
                         ? (isFinal ? "Final Invoice" : "Invoice")
                         : "\(isFinal ? "Final Invoice" : "Invoice") \(invoice.invoiceNumber)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
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

    // MARK: - Deletes

    private func deleteInvoices(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredInvoices[index])
        }
        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }
}

// MARK: - Templates (unchanged)

private extension InvoiceListView {

    func builtInTemplates() -> [InvoiceTemplate] {
        [
            InvoiceTemplate(
                title: "Basic Service",
                description: "One service line item with standard terms.",
                defaultLineItems: [
                    InvoiceTemplateLineItem(description: "Service", quantity: 1, unitPrice: 0)
                ],
                defaultPaymentTerms: "Net 14",
                defaultNotes: "Thanks for your business!",
                defaultTaxRate: 0,
                defaultDiscount: 0
            ),
            InvoiceTemplate(
                title: "Photography Session",
                description: "Session fee + standard note (edit pricing later).",
                defaultLineItems: [
                    InvoiceTemplateLineItem(description: "Photography Session", quantity: 1, unitPrice: 0)
                ],
                defaultPaymentTerms: "Due on receipt",
                defaultNotes: "Thank you for booking!",
                defaultTaxRate: 0,
                defaultDiscount: 0
            )
        ]
    }

    func createInvoiceFromTemplate(_ template: InvoiceTemplate) {
        do {
            guard let bizID = activeBiz.activeBusinessID else {
                print("❌ No active business selected")
                return
            }

            let profile: BusinessProfile = profiles.first(where: { $0.businessID == bizID }) ?? {
                let created = BusinessProfile(businessID: bizID)
                modelContext.insert(created)
                return created
            }()

            let newNumber = InvoiceNumberGenerator.generateNextNumber(profile: profile)

            let invoice = Invoice(
                businessID: bizID,
                invoiceNumber: newNumber,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                paymentTerms: template.defaultPaymentTerms,
                notes: template.defaultNotes,
                taxRate: template.defaultTaxRate,
                discountAmount: template.defaultDiscount,
                isPaid: false,
                documentType: "invoice",
                client: nil,
                items: []
            )

            if invoice.items == nil { invoice.items = [] }

            for li in template.defaultLineItems {
                let newItem = LineItem(
                    itemDescription: li.description,
                    quantity: li.quantity,
                    unitPrice: li.unitPrice
                )
                invoice.items?.append(newItem)
                newItem.invoice = invoice
            }

            modelContext.insert(invoice)
            try modelContext.save()

            showingTemplates = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                navigateToInvoice = invoice
            }
        } catch {
            print("Failed to create invoice from template: \(error)")
        }
    }
}
