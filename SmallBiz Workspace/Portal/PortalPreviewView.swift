import SwiftUI
import SwiftData

struct PortalPreviewView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \PortalAuditEvent.createdAt, order: .reverse) private var audit: [PortalAuditEvent]

    @State private var selectedClientID: UUID? = nil

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
            .foregroundStyle(.red)

            
            Button("Debug: Count Portal Identities") {
                run("Checked identities") { _, clientID in
                    let id = clientID
                    let fd = FetchDescriptor<PortalIdentity>(predicate: #Predicate { $0.clientID == id })
                    let matches = try modelContext.fetch(fd)
                    infoText = "PortalIdentity rows: \(matches.count) • enabled: \(matches.filter{$0.isEnabled}.count)"
                }
            }

            
            

            Button("Create Invite (Preview)") {
                run("Created invite") { service, clientID in
                    let result = try service.createInvite(clientID: clientID)

                    // 🔴 ADD THIS LINE
                    try modelContext.save()

                    codeOrTokenShown = result.rawCode

                    service.log(
                        clientID: clientID,
                        sessionID: nil,
                        origin: PortalActionOrigin.internalApp,
                        eventType: "portal.invite.created"
                    )
                }
            }


            Button("Mark Invite as Sent") {
                run("Marked invite as sent") { service, clientID in
                    // Fetch newest invites, then filter in-memory by clientID
                    var fd = FetchDescriptor<PortalInvite>(
                        sortBy: [SortDescriptor(\PortalInvite.createdAt, order: .reverse)]
                    )
                    fd.fetchLimit = 50

                    let recent = try modelContext.fetch(fd)
                    guard let invite = recent.first(where: { $0.clientID == clientID }) else {
                        throw simple("No invite found. Tap “Create Invite (Preview)” first.")
                    }

                    try service.markInviteSent(invite)
                }
            }


            Button("Accept Invite → Create Session") {
                run("Accepted invite + created session") { service, clientID in
                    guard let rawInviteCode = codeOrTokenShown, !rawInviteCode.isEmpty else {
                        throw simple("No invite code shown. Tap “Create Invite (Preview)” first.")
                    }

                    guard let result = try service.acceptInviteAndCreateSession(rawInviteCode: rawInviteCode) else {
                        throw simple("Invite is invalid, expired, revoked, or already accepted.")
                    }

                    // Show the session token
                    codeOrTokenShown = result.rawToken

                    // Optional log marker
                    service.log(
                        clientID: clientID,
                        sessionID: result.session.id,
                        origin: PortalActionOrigin.portal,
                        eventType: "portal.session.created"
                    )
                }
            }
        }
    }
    
    


    private var outputSection: some View {
        Group {
            if let codeOrTokenShown {
                Section("Output (shown once)") {
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

    private func simple(_ message: String) -> NSError {
        NSError(domain: "PortalPreview", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
