import SwiftUI
import SwiftData

/// Opt-in, client-facing overdue-payment email reminders.
///
/// The setting lives locally on `BusinessProfile` like everything else in
/// Business settings, but the cron job that actually sends the reminder runs
/// server-side with no other way to see on-device state — so every change
/// here also gets pushed up via `PortalBackend.syncOverdueReminderSettings`.
/// A sync failure never blocks the local save; it just means the server
/// keeps acting on whatever it last received until the next successful sync.
struct OverdueReminderSettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var isSyncing = false
    @State private var syncError: String?

    private let cadenceOptions = [3, 7, 14]

    var body: some View {
        Form {
            Section {
                Toggle("Remind Overdue Clients", isOn: Binding(
                    get: { profile?.overdueReminderEnabled ?? false },
                    set: { newValue in
                        Haptics.lightTap()
                        profile?.overdueReminderEnabled = newValue
                        saveAndSync()
                    }
                ))
            } footer: {
                Text("Sends one automatic email to a client when their invoice becomes overdue by the interval below. Only clients with Client Portal enabled can be reminded, and each invoice is only reminded once.")
            }

            if profile?.overdueReminderEnabled == true {
                Section("Remind After") {
                    Picker("Days overdue", selection: Binding(
                        get: { profile?.overdueReminderCadenceDays ?? 7 },
                        set: { newValue in
                            profile?.overdueReminderCadenceDays = newValue
                            saveAndSync()
                        }
                    )) {
                        ForEach(cadenceOptions, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
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
        .navigationTitle("Overdue Reminders")
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
            SBWLog.ui.problem("Failed to save overdue reminder settings: \(error)")
        }

        guard let profile else { return }
        let enabled = profile.overdueReminderEnabled
        let cadenceDays = profile.overdueReminderCadenceDays

        isSyncing = true
        Task {
            do {
                try await PortalBackend.shared.syncOverdueReminderSettings(
                    enabled: enabled,
                    cadenceDays: cadenceDays
                )
            } catch {
                syncError = "This setting is saved on your device but couldn't reach the server, so automatic reminders won't run until it syncs. \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}
