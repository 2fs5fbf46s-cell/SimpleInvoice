import SwiftUI
import SwiftData

struct EstimateDefaultsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var profile: BusinessProfile?
    @State private var business: Business?
    @State private var taxRatePercentText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let profile, let business {
                    EstimateDefaultsCard(profile: profile, business: business, taxRatePercentText: $taxRatePercentText)
                } else {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to configure estimate defaults.")
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Estimate Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    try? modelContext.save()
                }
            }
        }
        .onAppear(perform: loadActiveBusinessData)
    }

    private func loadActiveBusinessData() {
        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        } catch {
            // Continue with snapshot.
        }

        guard let bizID = activeBiz.activeBusinessID else {
            business = nil
            profile = nil
            return
        }

        business = businesses.first(where: { $0.id == bizID })

        if let existing = profiles.first(where: { $0.businessID == bizID }) {
            profile = existing
        } else {
            let created = BusinessProfile(businessID: bizID)
            modelContext.insert(created)
            try? modelContext.save()
            profile = created
        }

        if let business {
            let fraction = NSDecimalNumber(decimal: business.defaultTaxRate).doubleValue
            taxRatePercentText = String(format: "%.2f", max(0, fraction * 100.0))
        }
    }
}

private struct EstimateDefaultsCard: View {
    @Bindable var profile: BusinessProfile
    @Bindable var business: Business
    @Binding var taxRatePercentText: String

    var body: some View {
        SummaryKit.SummaryCard {
            SummaryKit.SummaryHeader(
                title: "Estimate Defaults",
                subtitle: "Pre-fill estimate values"
            )

            Stepper(value: $business.defaultEstimateValidityDays, in: 1...120) {
                SummaryKit.SummaryKeyValueRow(
                    label: "Validity Window",
                    value: "\(business.defaultEstimateValidityDays) day\(business.defaultEstimateValidityDays == 1 ? "" : "s")"
                )
            }

            multilineField("Default Payment Terms", placeholder: "Valid for 14 days", text: $profile.defaultEstimatePaymentTerms, lines: 1...4)
            multilineField("Default Notes", placeholder: "Estimate notes", text: $profile.defaultEstimateNotes, lines: 2...6)
            multilineField("Default Thank You", placeholder: "Thank you footer", text: $profile.defaultEstimateThankYou, lines: 2...6)
            multilineField("Default Terms & Conditions", placeholder: "Estimate terms", text: $profile.defaultEstimateTerms, lines: 3...8)

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
                    .onChange(of: taxRatePercentText) { _, newValue in
                        let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.isEmpty {
                            business.defaultTaxRate = 0
                            return
                        }
                        if let percent = Double(cleaned) {
                            business.defaultTaxRate = Decimal(max(0, percent) / 100.0)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Default Currency")
                    .font(.subheadline.weight(.semibold))
                TextField("USD", text: $business.currencyCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func multilineField(_ title: String, placeholder: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(lines)
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
