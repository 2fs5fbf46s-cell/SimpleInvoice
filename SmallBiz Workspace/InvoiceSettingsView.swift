import SwiftUI
import SwiftData

struct InvoiceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var profile: BusinessProfile?
    @State private var business: Business?
    @State private var showInvoiceTemplateSheet = false

    var body: some View {
        List {
            if let profile, let business {
                SummaryKit.SummaryCard {
                    SummaryKit.SummaryHeader(
                        title: "Defaults",
                        subtitle: "Pre-fill invoice values"
                    )

                    Button {
                        showInvoiceTemplateSheet = true
                    } label: {
                        SummaryKit.SummaryListRow(
                            icon: "doc.badge.gearshape",
                            title: "Default Invoice Template",
                            secondary: resolvedTemplate(for: business).displayName
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thank You")
                            .font(.subheadline.weight(.semibold))
                        TextField("Default Thank You", text: Bindable(profile).defaultThankYou, axis: .vertical)
                            .lineLimit(2...6)
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terms")
                            .font(.subheadline.weight(.semibold))
                        TextField("Default Terms & Conditions", text: Bindable(profile).defaultTerms, axis: .vertical)
                            .lineLimit(4...10)
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to configure invoice defaults.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Invoice Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadActiveBusinessData)
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            loadActiveBusinessData()
        }
        .onChange(of: profile?.defaultThankYou ?? "") { _, _ in
            try? modelContext.save()
        }
        .onChange(of: profile?.defaultTerms ?? "") { _, _ in
            try? modelContext.save()
        }
        .sheet(isPresented: $showInvoiceTemplateSheet) {
            NavigationStack {
                if let business {
                    let businessDefault = resolvedTemplate(for: business)
                    InvoiceTemplatePickerSheet(
                        mode: .businessDefault,
                        businessDefault: businessDefault,
                        currentEffective: businessDefault,
                        currentSelection: businessDefault,
                        onSelectTemplate: { selected in
                            business.defaultInvoiceTemplateKey = selected.rawValue
                            try? modelContext.save()
                        },
                        onUseBusinessDefault: {
                            // No-op in business default mode.
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showInvoiceTemplateSheet = false }
                        }
                    }
                } else {
                    ContentUnavailableView("No Business Selected", systemImage: "building.2")
                }
            }
        }
    }

    private func loadActiveBusinessData() {
        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        } catch {
            // Continue with current query snapshot.
        }

        guard let bizID = activeBiz.activeBusinessID else {
            business = nil
            profile = nil
            return
        }

        business = businesses.first(where: { $0.id == bizID })

        if let existing = profiles.first(where: { $0.businessID == bizID }) {
            profile = existing
            return
        }

        let created = BusinessProfile(businessID: bizID)
        modelContext.insert(created)
        try? modelContext.save()
        profile = created
    }

    private func resolvedTemplate(for business: Business) -> InvoiceTemplateKey {
        if let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) {
            return key
        }
        return .modern_clean
    }
}
