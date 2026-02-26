import SwiftUI
import SwiftData

struct InvoiceSettingsView: View {
    enum Mode {
        case invoice
        case estimate

        var navigationTitle: String {
            switch self {
            case .invoice: return "Invoice Settings"
            case .estimate: return "Estimate Settings"
            }
        }

        var subtitle: String {
            switch self {
            case .invoice: return "Pre-fill invoice values"
            case .estimate: return "Pre-fill estimate values"
            }
        }

        var showInvoiceTemplate: Bool {
            self == .invoice
        }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    let mode: Mode

    @State private var profile: BusinessProfile?
    @State private var business: Business?
    @State private var showInvoiceTemplateSheet = false
    @State private var taxRatePercentText = ""

    init(mode: Mode = .invoice) {
        self.mode = mode
    }

    var body: some View {
        List {
            if let profile, let business {
                SummaryKit.SummaryCard {
                    SummaryKit.SummaryHeader(
                        title: "Defaults",
                        subtitle: mode.subtitle
                    )

                    if mode.showInvoiceTemplate {
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
                    }

                    Stepper(value: Bindable(business).defaultEstimateValidityDays, in: 1...120) {
                        SummaryKit.SummaryKeyValueRow(
                            label: "Estimate Validity",
                            value: "\(business.defaultEstimateValidityDays) day\(business.defaultEstimateValidityDays == 1 ? "" : "s")"
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Tax Rate (%)")
                            .font(.subheadline.weight(.semibold))
                        TextField("0.0", text: $taxRatePercentText)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Applied to new estimates. Conversion keeps the estimate tax as-is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Currency Code")
                            .font(.subheadline.weight(.semibold))
                        TextField("USD", text: Bindable(business).currencyCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

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

                    Text("Deposit defaults are not configured globally in this app. Deposit values are preserved from the estimate when converting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to configure defaults.")
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
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadActiveBusinessData)
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            loadActiveBusinessData()
        }
        .onChange(of: business?.defaultTaxRate.description ?? "") { _, _ in
            syncTaxTextFromBusiness()
        }
        .onChange(of: taxRatePercentText) { _, newValue in
            saveTaxRatePercent(newValue)
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
            syncTaxTextFromBusiness()
            return
        }

        let created = BusinessProfile(businessID: bizID)
        modelContext.insert(created)
        try? modelContext.save()
        profile = created
        syncTaxTextFromBusiness()
    }

    private func resolvedTemplate(for business: Business) -> InvoiceTemplateKey {
        if let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) {
            return key
        }
        return .modern_clean
    }

    private func syncTaxTextFromBusiness() {
        guard let business else { return }
        let fraction = NSDecimalNumber(decimal: business.defaultTaxRate).doubleValue
        taxRatePercentText = String(format: "%.2f", max(0, fraction * 100.0))
    }

    private func saveTaxRatePercent(_ raw: String) {
        guard let business else { return }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            business.defaultTaxRate = 0
            try? modelContext.save()
            return
        }
        guard let percent = Double(cleaned) else { return }
        let normalized = max(0, percent) / 100.0
        business.defaultTaxRate = Decimal(normalized)
        try? modelContext.save()
    }
}
