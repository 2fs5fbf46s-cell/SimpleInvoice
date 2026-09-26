import SwiftUI
import SwiftData

/// Opt-in, client-facing "your appointment is tomorrow" email reminders.
///
/// Mirrors `OverdueReminderSettingsView` exactly: the toggle lives locally on
/// `BusinessProfile`, but the cron job that actually sends the reminder runs
/// server-side against Job data the device pushes up separately (see
/// `PortalBackend.syncJobScheduleReminder`) — so every change here also gets
/// pushed via `PortalBackend.syncAppointmentReminderSettings`. A sync failure
/// never blocks the local save; it just means the server keeps acting on
/// whatever it last received until the next successful sync.
struct AppointmentReminderSettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Remind Clients of Upcoming Jobs", isOn: Binding(
                    get: { profile?.appointmentRemindersEnabled ?? false },
                    set: { newValue in
                        Haptics.lightTap()
                        profile?.appointmentRemindersEnabled = newValue
                        saveAndSync()
                    }
                ))
            } footer: {
                Text("Sends one automatic email to a client about 24 hours before a scheduled job, as long as the job has a client and a confirmed date.")
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
        .navigationTitle("Appointment Reminders")
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
            SBWLog.ui.problem("Failed to save appointment reminder settings: \(error)")
        }

        guard let profile else { return }
        let enabled = profile.appointmentRemindersEnabled

        isSyncing = true
        Task {
            do {
                try await PortalBackend.shared.syncAppointmentReminderSettings(enabled: enabled)
            } catch {
                syncError = "This setting is saved on your device but couldn't reach the server, so appointment reminders won't run until it syncs. \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}
