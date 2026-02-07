import SwiftUI
import SwiftData

/// A lightweight "portal directory" launcher.
/// Pick a client -> open their portal directory.
struct PortalDirectoryLauncherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: [SortDescriptor(\Client.name, order: .forward)])
    private var clients: [Client]

    @State private var searchText: String = ""

    @State private var opening = false
    @State private var portalURL: URL? = nil
    @State private var showPortal = false
    @State private var errorText: String? = nil
    @State private var navigateToClientSettings: Client? = nil

    // MARK: - Scoping

    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }

    private var filtered: [Client] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return scopedClients }

        return scopedClients.filter {
            $0.name.lowercased().contains(q)
            || $0.email.lowercased().contains(q)
            || $0.phone.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            List {
                if let errorText {
                    Text(errorText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        scopedClients.isEmpty ? "No Clients Yet" : "No Results",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        description: Text(scopedClients.isEmpty
                                          ? "Create a client first, then enable their portal to share files."
                                          : "Try a different search.")
                    )
                } else {
                    ForEach(filtered) { c in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                Task { await openDirectory(for: c) }
                            } label: {
                                row(c)
                            }
                            .buttonStyle(.plain)
                            .disabled(opening || !c.portalEnabled)
                            .opacity((opening || !c.portalEnabled) ? 0.55 : 1)

                            if !c.portalEnabled {
                                Text("Client portal is disabled.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    navigateToClientSettings = c
                                } label: {
                                    Label("Enable Client Portal", systemImage: "togglepower")
                                }
                                .buttonStyle(.bordered)
                                .tint(SBWTheme.brandBlue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Client Portal")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search clients"
        )
        .navigationDestination(item: $navigateToClientSettings) { client in
            ClientEditView(client: client)
        }
        .sheet(isPresented: $showPortal) {
            if let url = portalURL {
                SafariView(url: url, onDone: {})
            }
        }
        .toolbar {
            if opening {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
    }

    // MARK: - Row UI (Option A parity)

    private func row(_ c: Client) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Leading icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Client Portal"))
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : c.name)
                        .font(.headline)

                    Spacer()

                    if !c.portalEnabled {
                        Text("DISABLED")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemFill))
                            .clipShape(Capsule())
                    }
                }

                if !c.email.isEmpty {
                    Text(c.email)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !c.phone.isEmpty {
                    Text(c.phone)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .foregroundStyle(.secondary)
                }

            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Open

    @MainActor
    private func openDirectory(for client: Client) async {
        opening = true
        errorText = nil
        defer { opening = false }

        do {
            // new PortalBackend signature (no mode param)
            let token = try await PortalBackend.shared.createClientDirectoryPortalToken(client: client)

            // new URL builder name
            let url = PortalBackend.shared.portalClientDirectoryURL(
                clientId: client.id.uuidString,
                token: token
            )

            portalURL = url
            showPortal = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
