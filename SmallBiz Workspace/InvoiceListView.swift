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

    // Navigate to the invoice created from a template
    @State private var navigateToInvoice: Invoice? = nil
    @State private var selectedInvoice: Invoice? = nil

    // MARK: - Filters
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unpaid = "Unpaid"
        case paid = "Paid"

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
                if filteredInvoices.isEmpty {
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search invoices"
        )
        

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
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewInvoice = true } label: {
                    Image(systemName: "plus")
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

        // Navigate to created invoice after template selection
        .navigationDestination(item: $navigateToInvoice) { invoice in
            InvoiceDetailView(invoice: invoice)
        }
        .navigationDestination(item: $selectedInvoice) { invoice in
            InvoiceDetailView(invoice: invoice)
        }
    }


    // MARK: - Filtered data (✅ excludes estimates)

    private var filteredInvoices: [Invoice] {
        let nonEstimates = scopedInvoices.filter { $0.documentType != "estimate" }

        let base: [Invoice]
        switch filter {
        case .all:
            base = nonEstimates
        case .paid:
            base = nonEstimates.filter { $0.isPaid }
        case .unpaid:
            base = nonEstimates.filter { !$0.isPaid }
        }

        guard !searchText.isEmpty else { return base }

        return base.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(searchText) ||
            ($0.client?.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var scopedInvoices: [Invoice] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
    }

    // MARK: - Row UI (Option A polish: icon chip + content)

    private func row(_ invoice: Invoice) -> some View {
        let statusText = invoice.isPaid ? "PAID" : "UNPAID"
        let clientName = invoice.client?.name ?? "No Client"
        let date = invoice.issueDate.formatted(date: .abbreviated, time: .omitted)
        let total = invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let subtitle = "\(statusText) • \(clientName) • \(date) • \(total)"

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

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invoice.invoiceNumber.isEmpty ? "Invoice" : "Invoice \(invoice.invoiceNumber)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
