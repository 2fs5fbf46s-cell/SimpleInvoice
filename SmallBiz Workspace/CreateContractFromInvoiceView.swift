import SwiftUI
import SwiftData

struct CreateContractFromInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var invoice: Invoice

    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedTemplate: ContractTemplate?
    @State private var previewText: String = ""
    @State private var showPreview = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Template") {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates Found",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Templates should seed on launch.")
                    )
                } else {
                    Picker("Choose Template", selection: $selectedTemplate) {
                        Text("Select…").tag(Optional<ContractTemplate>.none)
                        ForEach(templates) { t in
                            Text("\(t.name) (\(t.category))").tag(Optional(t))
                        }
                    }
                }
            }

            Section("Invoice") {
                Text("Invoice \(invoice.invoiceNumber)")
                Text(invoice.client?.name ?? "No Client")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    generatePreview()
                } label: {
                    Label("Preview", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTemplate == nil)

                Button {
                    saveDraft()
                } label: {
                    Label("Save Draft", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selectedTemplate == nil)
            }
        }
        .navigationTitle("Create Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ScrollView {
                    Text(previewText.isEmpty ? "Nothing to preview." : previewText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showPreview = false }
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorText != nil), actions: {
            Button("OK") { errorText = nil }
        }, message: {
            Text(errorText ?? "Unknown error.")
        })
        .onAppear {
            if selectedTemplate == nil { selectedTemplate = templates.first }
        }
    }

    private var business: BusinessProfile? { profiles.first }

    private func generatePreview() {
        guard let template = selectedTemplate else { return }
        let ctx = ContractContext(business: business, client: invoice.client, invoice: invoice)
        previewText = ContractTemplateEngine.render(template: template.body, context: ctx)
        showPreview = true
    }

    private func saveDraft() {
        guard let template = selectedTemplate else { return }
        do {
            _ = try ContractCreation.create(
                context: modelContext,
                template: template,
                business: business,
                client: invoice.client,
                invoice: invoice
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
