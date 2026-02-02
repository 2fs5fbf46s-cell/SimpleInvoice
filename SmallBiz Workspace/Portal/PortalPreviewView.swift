import SwiftUI
import SwiftData

/// Internal developer tool to test the end-to-end client portal flow:
/// Enable portal → Create invite → Mark sent → Accept invite → Get *web* session token (payload.signature).
struct PortalPreviewView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \PortalAuditEvent.createdAt, order: .reverse) private var audit: [PortalAuditEvent]

    @State private var selectedClientID: UUID? = nil

    // Backend settings for preview tools (stored in UserDefaults via AppStorage)
    @AppStorage("PortalBackendBaseURL") private var portalBackendBaseURL: String = "https://smallbizworkspace-portal-backend.vercel.app"
    @AppStorage("PortalAdminKey") private var portalAdminKey: String = ""

    // Most recent invite code created in this view (needed for "Mark Sent" + "Accept")
    @State private var lastInviteCode: String? = nil

    // Shows invite code OR session token
    @State private var codeOrTokenShown: String? = nil

    // Visible feedback
    @State private var errorText: String? = nil
    @State private var infoText: String? = nil

    var body: some View {
        NavigationStack {
            List {
                clientSection
                portalControlsSection
                backendSettingsSection

                outputSection
                statusSection
                errorSection
                auditSection
            }
            .navigationTitle("Portal Preview")
        }
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Client") {
            Picker("Client", selection: $selectedClientID) {
                Text("Select…").tag(UUID?.none)
                ForEach(clients) { client in
                    Text(client.name).tag(UUID?.some(client.id))
                }
            }
        }
    }

    private var portalControlsSection: some View {
        Section("Portal Controls") {

            Button("Enable Portal for Selected Client") {
                run("Enabled portal") { service, clientID in
                    try service.setEnabled(true, clientID: clientID)
                }
            }

            Button("Disable Portal for Selected Client") {
                run("Disabled portal") { service, clientID in
                    try service.setEnabled(false, clientID: clientID)
                }
            }

            Button("Create Invite (Preview)") {
                run("Created invite") { service, clientID in
                    let result = try service.createInvite(clientID: clientID)
                    lastInviteCode = result.rawCode
                    codeOrTokenShown = result.rawCode
                }
            }

            Button("Mark Invite as Sent") {
                run("Marked invite as sent") { service, _ in
                    guard let code = lastInviteCode else {
                        throw simple("No invite code yet. Tap “Create Invite (Preview)” first.")
                    }
                    guard let invite = try service.validateInvite(rawCode: code) else {
                        throw simple("Invite not found/expired. Create a new invite.")
                    }
                    try service.markInviteSent(invite)
                }
            }

            Button("Accept Invite → Create Web Session") {
                runAsync("Accepted invite + created web session") { service, _ in
                    guard let code = lastInviteCode else {
                        throw simple("No invite code yet. Tap “Create Invite (Preview)” first.")
                    }

                    // Returns a real web token (payload.signature) from your Vercel backend seed endpoint.
                    guard let result = try await service.acceptInviteAndCreateRemoteSession(
                        rawInviteCode: code,
                        backendBaseURL: portalBackendBaseURL,
                        adminKey: portalAdminKey,
                        scope: "directory"
                    ) else {
                        throw simple("Invite invalid/expired. Create a new invite.")
                    }

                    await MainActor.run {
                        codeOrTokenShown = result.token
                    }
                }
            }
        }
    }

    private var backendSettingsSection: some View {
        Section("Backend Settings (Preview)") {
            TextField("Portal Backend Base URL", text: $portalBackendBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote)

            SecureField("Portal Admin Key", text: $portalAdminKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote)

            Text("Used only for Portal Preview tooling. Must match your Vercel env vars (PORTAL_ADMIN_KEY).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var outputSection: some View {
        Group {
            if let codeOrTokenShown {
                Section("Output (shown once)") {
                    let isToken = codeOrTokenShown.contains(".")
                    Text(isToken ? "Session Token (web portal)" : "Invite Code (not a token)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(codeOrTokenShown)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var statusSection: some View {
        Group {
            if let infoText {
                Section("Last Action") {
                    Text(infoText)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let errorText {
                Section("Error") {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var auditSection: some View {
        Section("Recent Portal Audit (latest 25)") {
            if audit.isEmpty {
                Text("No events yet. Use the buttons above to generate events.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(audit.prefix(25)) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.eventType)
                            .font(.headline)
                        Text("\(e.origin) • \(e.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let summary = e.summary, !summary.isEmpty {
                            Text(summary).font(.footnote)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func run(_ successMessage: String, _ work: (PortalService, UUID) throws -> Void) {
        errorText = nil
        infoText = nil

        do {
            guard let clientID = selectedClientID else {
                throw simple("Pick a client first.")
            }

            let service = PortalService(modelContext: modelContext)
            try work(service, clientID)

            infoText = successMessage
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runAsync(_ successMessage: String, _ work: @escaping (PortalService, UUID) async throws -> Void) {
        errorText = nil
        infoText = nil

        Task {
            do {
                guard let clientID = selectedClientID else {
                    throw simple("Pick a client first.")
                }

                let service = PortalService(modelContext: modelContext)
                try await work(service, clientID)

                await MainActor.run { infoText = successMessage }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func simple(_ message: String) -> NSError {
        NSError(domain: "PortalPreview", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
