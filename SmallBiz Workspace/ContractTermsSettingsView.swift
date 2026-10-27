import SwiftUI
import SwiftData

/// Business → Contract Terms: the cancellation tiers, final-balance
/// deadline and governing state new contracts are written with. Each
/// contract can still change them on the New Contract screen.
///
/// Local only: contracts are written on the device, so nothing syncs to
/// the server.
struct ContractTermsSettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var terms = ContractTerms()

    var body: some View {
        Form {
            Section {
                ContractTermsFields(terms: $terms)
            } footer: {
                Text("Used by the built-in Service, Photography and DJ agreements. Contracts you already made keep the terms they were written with.")
            }
        }
        .navigationTitle("Contract Terms")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .onAppear { resolveProfile() }
        .onChange(of: terms) { _, newValue in
            guard let profile else { return }
            newValue.save(to: profile)
            do {
                try modelContext.save()
            } catch {
                SBWLog.ui.problem("Failed to save contract terms: \(error)")
            }
        }
    }

    private func resolveProfile() {
        guard profile == nil, let bizID = activeBiz.activeBusinessID else { return }
        if let existing = profiles.first(where: { $0.businessID == bizID }) {
            profile = existing
        } else {
            let created = BusinessProfile(businessID: bizID)
            modelContext.insert(created)
            try? modelContext.save()
            profile = created
        }
        terms = ContractTerms(profile: profile).normalized
    }
}

/// The terms controls, shared by Contract Terms settings and the New
/// Contract screen. Every change keeps the tiers in order (see
/// `ContractTerms.normalized`).
struct ContractTermsFields: View {
    @Binding var terms: ContractTerms

    private func update(_ change: (inout ContractTerms) -> Void) {
        var next = terms
        change(&next)
        terms = next.normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(terms.summary(hasDeposit: true))
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("If the client cancels")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Stepper(value: Binding(get: { terms.cancelEarlyDays }, set: { v in update { $0.cancelEarlyDays = v } }),
                        in: (terms.cancelLateDays + 1)...180) {
                    Text("More than **\(terms.cancelEarlyDays) days** out: deposit kept")
                }
                Stepper(value: Binding(get: { terms.cancelMidPercent }, set: { v in update { $0.cancelMidPercent = v } }),
                        in: 0...100, step: 5) {
                    Text("\(terms.cancelLateDays + 1)–\(terms.cancelEarlyDays) days out: **\(terms.cancelMidPercent)%** of the total")
                }
                Stepper(value: Binding(get: { terms.cancelLateDays }, set: { v in update { $0.cancelLateDays = v } }),
                        in: 1...max(terms.cancelEarlyDays - 1, 1)) {
                    Text("Last **\(terms.cancelLateDays) days**")
                }
                Stepper(value: Binding(get: { terms.cancelLatePercent }, set: { v in update { $0.cancelLatePercent = v } }),
                        in: terms.cancelMidPercent...100, step: 5) {
                    Text("Inside \(terms.cancelLateDays) days: **\(terms.cancelLatePercent)%** of the total")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Final balance due")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Final balance due", selection: Binding(
                    get: { terms.balanceDueHours },
                    set: { v in update { $0.balanceDueHours = v } }
                )) {
                    ForEach(ContractTerms.balanceDueHourOptions, id: \.self) { hours in
                        Text("\(hours) hrs before").tag(hours)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Governing state")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. South Carolina", text: Binding(
                    get: { terms.governingState },
                    set: { v in terms.governingState = v }
                ))
                .textInputAutocapitalization(.words)
                Text(terms.governingState.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Blank: the state where your business operates."
                     : "Disputes go to a court in \(terms.governingState.trimmingCharacters(in: .whitespaces)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
