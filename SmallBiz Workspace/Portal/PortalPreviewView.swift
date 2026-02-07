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
    @State private var showAllAudit = false
    @State private var showDeveloperSettings = false

    private var selectedClientName: String {
        guard let id = selectedClientID,
              let client = clients.first(where: { $0.id == id }) else {
            return "No client selected"
        }
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Client" : name
    }

    private var previewStatus: String {
        if errorText != nil { return "ERROR" }
        if infoText != nil { return "READY" }
        return "IDLE"
    }

    private var visibleAudit: ArraySlice<PortalAuditEvent> {
        audit.prefix(showAllAudit ? 25 : 3)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                clientCard
                portalControlsCard
                outputCard
                statusCard
                errorCard
                auditCard
                developerSettingsCard
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .top) { pinnedHeader }
        .navigationTitle("Portal Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var pinnedHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedClientName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Portal Preview Tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(previewStatus)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Capsule().fill(SBWTheme.chip(forStatus: previewStatus).bg))
                .foregroundStyle(SBWTheme.chip(forStatus: previewStatus).fg)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var clientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Client", selection: $selectedClientID) {
                Text("Select…").tag(UUID?.none)
                ForEach(clients) { client in
                    Text(client.name).tag(UUID?.some(client.id))
                }
            }
        }
        .sbwPortalCardRow()
    }

    private var portalControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Portal Controls")

            Button("Enable Portal for Selected Client") {
                run("Enabled portal") { service, clientID in
                    try service.setEnabled(true, clientID: clientID)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(SBWTheme.brandBlue)

            Button("Disable Portal for Selected Client") {
                run("Disabled portal") { service, clientID in
                    try service.setEnabled(false, clientID: clientID)
                }
            }
            .buttonStyle(.bordered)

            Button("Create Invite (Preview)") {
                run("Created invite") { service, clientID in
                    let result = try service.createInvite(clientID: clientID)
                    lastInviteCode = result.rawCode
                    codeOrTokenShown = result.rawCode
                }
            }
            .buttonStyle(.bordered)

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
            .buttonStyle(.bordered)

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
            .buttonStyle(.borderedProminent)
            .tint(SBWTheme.brandGreen)
        }
        .sbwPortalCardRow()
    }

    private var developerSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Developer Settings", isOn: $showDeveloperSettings)
                .font(.subheadline.weight(.semibold))

            if showDeveloperSettings {
                sectionTitle("Backend Settings")

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
        .sbwPortalCardRow()
    }

    private var outputCard: some View {
        Group {
            if let codeOrTokenShown {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Output")
                    let isToken = codeOrTokenShown.contains(".")
                    Text(isToken ? "Session Token (web portal)" : "Invite Code (not a token)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(codeOrTokenShown)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                }
                .sbwPortalCardRow()
            }
        }
    }

    private var statusCard: some View {
        Group {
            if let infoText {
                Text(infoText)
                    .foregroundStyle(.secondary)
                    .sbwPortalCardRow()
            }
        }
    }

    private var errorCard: some View {
        Group {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .sbwPortalCardRow()
            }
        }
    }

    private var auditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recent Portal Audit")
            if audit.isEmpty {
                Text("No events yet. Use the buttons above to generate events.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleAudit) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(SBWTheme.brandBlue.opacity(0.65))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.eventType)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(e.origin) • \(e.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let summary = e.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if audit.count > 3 {
                    Button(showAllAudit ? "Show Less" : "Show More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllAudit.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                }
            }
        }
        .sbwPortalCardRow()
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(SBWTheme.brandBlue)
                .frame(width: 4, height: 16)
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
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

private struct SBWPortalCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func sbwPortalCardRow() -> some View {
        modifier(SBWPortalCardRow())
    }
}
