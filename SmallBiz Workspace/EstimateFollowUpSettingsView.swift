import SwiftUI
import SwiftData

/// Opt-in, client-facing follow-up emails on estimates the client hasn't
/// answered.
///
/// Mirrors `OverdueReminderSettingsView`: the setting lives locally on
/// `BusinessProfile`, and every change is pushed up via
/// `PortalBackend.syncEstimateFollowUpSettings` for the server's cron job.
/// A sync failure never blocks the local save.
struct EstimateFollowUpSettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var isSyncing = false
    @State private var syncError: String?

    private let dayOptions = [3, 5, 7]

    private var afterDays: Int { profile?.estimateFollowUpAfterDays ?? 3 }

    var body: some View {
        Form {
            Section {
                Toggle("Follow Up on Estimates", isOn: Binding(
                    get: { profile?.estimateFollowUpEnabled ?? false },
                    set: { newValue in
                        Haptics.lightTap()
                        profile?.estimateFollowUpEnabled = newValue
                        saveAndSync()
                    }
                ))
            } footer: {
                Text("When a client hasn't accepted or declined an estimate you sent, they get a friendly reminder email with a link to it. It stops as soon as they answer, and starts over if you revise and resend.")
            }

            if profile?.estimateFollowUpEnabled == true {
                Section {
                    Picker("Days without an answer", selection: Binding(
                        get: { afterDays },
                        set: { newValue in
                            profile?.estimateFollowUpAfterDays = newValue
                            saveAndSync()
                        }
                    )) {
                        ForEach(dayOptions, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Follow Up After")
                } footer: {
                    Text("First reminder \(afterDays) days after you send it, a last one at \(afterDays * 2) days. You'll get a notification each time.")
                }
            }

            if isSyncing {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Estimate Follow-ups")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .onAppear { resolveProfile() }
        .alert("Sync Failed", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK", role: .cancel) { syncError = nil }
        } message: {
            Text(syncError ?? "")
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
    }

    private func saveAndSync() {
        do {
            try modelContext.save()
        } catch {
            SBWLog.ui.problem("Failed to save estimate follow-up settings: \(error)")
        }

        guard let profile else { return }
        let enabled = profile.estimateFollowUpEnabled
        let afterDays = profile.estimateFollowUpAfterDays

        isSyncing = true
        Task {
            do {
                try await PortalBackend.shared.syncEstimateFollowUpSettings(
                    enabled: enabled,
                    afterDays: afterDays
                )
            } catch {
                syncError = "This setting is saved on your device but couldn't reach the server, so follow-ups won't go out until it syncs. \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}
