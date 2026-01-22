//
//  CreateMenuSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct CreateMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [BusinessProfile]

    // Navigation targets created here
    @State private var createdInvoice: Invoice? = nil

    // Booking creation sheet
    @State private var showNewBooking = false

    var body: some View {
        NavigationStack {
            List {

                Section("Billing") {
                    Button {
                        createInvoice(documentType: "invoice")
                    } label: {
                        Label("New Invoice", systemImage: "doc.plaintext")
                    }

                    Button {
                        createInvoice(documentType: "estimate")
                    } label: {
                        Label("New Estimate", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section("Scheduling") {
                    Button {
                        showNewBooking = true
                    } label: {
                        Label("New Booking", systemImage: "calendar.badge.clock")
                    }
                }

                Section("Customers & Requests") {
                    Button {
                        // Scaffold for now (wire later)
                        dismiss()
                    } label: {
                        Label("New Client", systemImage: "person.badge.plus")
                    }

                    Button {
                        // Scaffold for now (wire later)
                        dismiss()
                    } label: {
                        Label("New Request", systemImage: "tray.full")
                    }
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }

            // Navigate into invoice/estimate editor after creating the record
            .navigationDestination(item: $createdInvoice) { inv in
                InvoiceDetailView(invoice: inv)
            }

            // New booking flow
            .sheet(isPresented: $showNewBooking) {
                NavigationStack {
                    NewBookingView()
                }
            }
        }
    }

    private func createInvoice(documentType: String) {
        let isEstimate = (documentType == "estimate")

        // Create a draft record (numbering handled later; estimate can stay draft)
        let invoice = Invoice(
            invoiceNumber: isEstimate ? "EST-DRAFT" : "DRAFT",
            documentType: documentType,
            items: []
        )

        // Preload defaults from Business Profile (if present)
        if let p = profiles.first {
            if invoice.thankYou.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invoice.thankYou = p.defaultThankYou
            }
            if invoice.termsAndConditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invoice.termsAndConditions = p.defaultTerms
            }
        }

        modelContext.insert(invoice)
        try? modelContext.save()

        // Push to detail editor
        createdInvoice = invoice
    }
}
