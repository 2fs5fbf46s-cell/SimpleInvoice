import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct BusinessProfileView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var profile: BusinessProfile?

    var body: some View {
        Group {
            if let profile {
                Form {
                    Section("Workspace") {
                        NavigationLink("Switch Business") {
                            BusinessSwitcherView()
                        }

                        if let id = activeBiz.activeBusinessID {
                            Text("Active Business ID: \(id.uuidString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Logo") {
                        if let logoData = profile.logoData,
                           let uiImage = UIImage(data: logoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(12)
                                .padding(.vertical, 8)
                        } else {
                            ContentUnavailableView(
                                "No Logo",
                                systemImage: "photo",
                                description: Text("Select a logo to appear on your invoices.")
                            )
                        }

                        PhotosPicker(selection: $selectedLogoItem,
                                     matching: .images,
                                     photoLibrary: .shared()) {
                            Label("Choose Logo", systemImage: "photo.on.rectangle")
                        }

                        if profile.logoData != nil {
                            Button(role: .destructive) {
                                profile.logoData = nil
                                selectedLogoItem = nil
                                try? modelContext.save()
                            } label: {
                                Label("Remove Logo", systemImage: "trash")
                            }
                        }
                    }

                    Section("Business") {
                        TextField("Business Name", text: Bindable(profile).name)
                        TextField("Email", text: Bindable(profile).email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        TextField("Phone", text: Bindable(profile).phone)
                            .keyboardType(.phonePad)
                    }

                    Section("Address") {
                        TextField("Address", text: Bindable(profile).address, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    // ✅ Defaults used on every invoice
                    Section("Invoice Defaults") {
                        TextField("Default Thank You", text: Bindable(profile).defaultThankYou, axis: .vertical)
                            .lineLimit(2...6)

                        TextField("Default Terms & Conditions", text: Bindable(profile).defaultTerms, axis: .vertical)
                            .lineLimit(4...10)

                        Text("These are printed on every invoice PDF (unless you override them per invoice).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Saved Item Categories") {
                        TextField("Categories (one per line)", text: Bindable(profile).catalogCategoriesText, axis: .vertical)
                            .lineLimit(6...14)

                        Text("Tip: One category per line. Example:\nPhotography\nDJ\nAudio/Visual")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Invoice Numbering") {
                        TextField("Prefix (e.g. SI, JF, SWIFT)", text: Bindable(profile).invoicePrefix)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        Stepper(value: Bindable(profile).nextInvoiceNumber, in: 1...999999) {
                            Text("Next Invoice Number: \(profile.nextInvoiceNumber)")
                        }

                        let year = Calendar.current.component(.year, from: .now)
                        Text("Example: \(profile.invoicePrefix)-\(year)-\(String(format: "%03d", profile.nextInvoiceNumber))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(role: .destructive) {
                            let year = Calendar.current.component(.year, from: .now)
                            profile.lastInvoiceYear = year
                            profile.nextInvoiceNumber = 1
                            try? modelContext.save()
                        } label: {
                            Label("Reset to 001", systemImage: "arrow.counterclockwise")
                        }
                    }

                    Section {
                        Text("This info will appear on your invoice PDFs.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Business Profile")
                .onChange(of: selectedLogoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            profile.logoData = data
                            try? modelContext.save()
                        }
                    }
                }
                // ✅ auto-save for text changes
                .onChange(of: profile.defaultThankYou) { _, _ in try? modelContext.save() }
                .onChange(of: profile.defaultTerms) { _, _ in try? modelContext.save() }
                .onChange(of: profile.catalogCategoriesText) { _, _ in try? modelContext.save() }
                .onChange(of: profile.invoicePrefix) { _, _ in try? modelContext.save() }
            } else {
                ProgressView("Loading…")
                    .navigationTitle("Business Profile")
            }
        }
        .onAppear {
            do {
                try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)

                guard let bizID = activeBiz.activeBusinessID else { return }

                // Find profile for this business
                if let existing = profiles.first(where: { $0.businessID == bizID }) {
                    self.profile = existing
                } else {
                    // Create one for this business
                    let created = BusinessProfile(businessID: bizID)
                    modelContext.insert(created)
                    try? modelContext.save()
                    self.profile = created
                }
            } catch {
                // optionally show an error state
                self.profile = profiles.first
            }
        }      
    }
}
