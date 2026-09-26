import SwiftUI
import SwiftData

/// Opt-in review-ask link shown on a paid invoice's client portal page.
///
/// Mirrors `OverdueReminderSettingsView`: the setting lives locally on
/// `BusinessProfile`, but the portal page renders it server-side on every
/// view (so a changed or disabled link never leaves a stale ask on an old
/// invoice) — so every change here also gets pushed up via
/// `PortalBackend.syncReviewRequestSettings`. A sync failure never blocks the
/// local save; it just means the server keeps acting on whatever it last
/// received until the next successful sync.
struct ReviewRequestSettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var linkText: String = ""
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Ask Paid Clients for a Review", isOn: Binding(
                    get: { profile?.reviewRequestEnabled ?? false },
                    set: { newValue in
                        Haptics.lightTap()
                        profile?.reviewRequestEnabled = newValue
                        saveAndSync()
                    }
                ))
            } footer: {
                Text("Once a client's invoice is marked paid, their client portal page shows a \"Leave a Review\" button linking wherever you'd like — Google, Yelp, or anywhere else.")
            }

            if profile?.reviewRequestEnabled == true {
                Section {
                    TextField("https://g.page/your-business/review", text: $linkText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commitLink() }
                } header: {
                    Text("Review Link")
                } footer: {
                    if let profile, profile.reviewRequestEnabled, profile.reviewLinkURL.isEmpty {
                        Text("Add a link above, then move to another field to save. Only https:// links are shown to clients.")
                    } else {
                        Text("Only https:// links are shown to clients.")
                    }
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
        .navigationTitle("Review Requests")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .onAppear { resolveProfile() }
        .onDisappear { commitLink() }
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
        linkText = profile?.reviewLinkURL ?? ""
    }

    private func commitLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != profile?.reviewLinkURL else { return }
        profile?.reviewLinkURL = trimmed
        saveAndSync()
    }

    private func saveAndSync() {
        do {
            try modelContext.save()
        } catch {
            SBWLog.ui.problem("Failed to save review request settings: \(error)")
        }

        guard let profile else { return }
        let enabled = profile.reviewRequestEnabled
        let link = profile.reviewLinkURL

        isSyncing = true
        Task {
            do {
                try await PortalBackend.shared.syncReviewRequestSettings(
                    enabled: enabled,
                    reviewLinkURL: link
                )
            } catch {
                syncError = "This setting is saved on your device but couldn't reach the server, so the review ask won't show to clients until it syncs. \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}
