//
//  ClientPortalCard.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// The client's portal on the client screen: whether they have one, a way
/// to look at it, and a way to send them the link.
///
/// This was an "Enable Client Portal" toggle near the top of the edit form
/// and two buttons inside Advanced Options, and the same switch was shown
/// elsewhere as ACTIVE/ARCHIVED, PORTAL ON/OFF and "Portal On".
struct ClientPortalCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var client: Client
    let businessName: String?

    @State private var opening = false
    @State private var portalURL: URL? = nil
    @State private var showLinkSheet = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { client.portalEnabled },
                set: { newValue in
                    client.portalEnabled = newValue
                    try? modelContext.save()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portal access")
                        .font(.subheadline.weight(.semibold))
                    Text(client.portalEnabled
                         ? "They can see what you've sent, sign, and pay online."
                         : "Off. You can't send them invoices or estimates by email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(SBWTheme.brandGreen)

            if client.portalEnabled {
                HStack(spacing: 10) {
                    Button {
                        openPortal()
                    } label: {
                        Label(opening ? "Opening…" : "View portal", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(opening)

                    Button {
                        showLinkSheet = true
                    } label: {
                        Label("Send link", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
                .tint(SBWTheme.brandBlue)
            }
        }
        .sheet(item: Binding(
            get: { portalURL.map { IdentifiableURL(url: $0) } },
            set: { portalURL = $0?.url }
        )) { item in
            SafariView(url: item.url, onDone: {})
        }
        .sheet(isPresented: $showLinkSheet) {
            ClientPortalLinkSheet(client: client, businessName: businessName)
        }
        .alert("Couldn’t Open Portal", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func openPortal() {
        opening = true
        Task {
            do {
                let token = try await PortalBackend.shared.createClientDirectoryPortalToken(
                    client: client,
                    mode: "live"
                )
                portalURL = PortalBackend.shared.buildClientDirectoryPortalURL(client: client, token: token)
            } catch {
                errorText = error.localizedDescription
            }
            opening = false
        }
    }
}

/// Emails and/or texts the client a link to their portal.
struct ClientPortalLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let client: Client
    let businessName: String?

    @State private var sendByEmail = false
    @State private var sendByText = false
    @State private var ttlDays = 7
    @State private var message = ""
    @State private var sending = false
    @State private var sentLink: String? = nil
    @State private var errorText: String? = nil

    private var email: String { client.email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var phone: String { client.phone.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $sendByEmail) {
                        LabeledContent("Email", value: email.isEmpty ? "No email" : email)
                    }
                    .disabled(email.isEmpty)
                    Toggle(isOn: $sendByText) {
                        LabeledContent("Text", value: phone.isEmpty ? "No phone" : phone)
                    }
                    .disabled(phone.isEmpty)
                } header: {
                    Text("Send to \(client.displayName)")
                } footer: {
                    if email.isEmpty && phone.isEmpty {
                        Text("Add an email or phone number to this client first.")
                    }
                }

                Section {
                    Stepper("Link works for \(ttlDays) day\(ttlDays == 1 ? "" : "s")", value: $ttlDays, in: 1...30)
                    TextField("Add a message (optional)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let sentLink {
                    Section("Sent") {
                        Text(sentLink)
                            .font(.footnote)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = sentLink
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }
                        if let url = URL(string: sentLink) {
                            ShareLink(item: url) {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send Portal Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentLink == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else if sentLink == nil {
                        Button("Send") { send() }
                            .fontWeight(.semibold)
                            .disabled(!sendByEmail && !sendByText)
                    }
                }
            }
            .alert("Couldn’t Send Link", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                sendByEmail = !email.isEmpty
                sendByText = email.isEmpty && !phone.isEmpty
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        sending = true
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                sentLink = try await PortalBackend.shared.sendPortalLink(
                    businessId: client.businessID.uuidString,
                    clientId: client.id.uuidString,
                    clientEmail: sendByEmail ? email : nil,
                    clientPhone: sendByText ? phone : nil,
                    businessName: businessName,
                    sendEmail: sendByEmail,
                    sendSms: sendByText,
                    ttlDays: ttlDays,
                    message: note.isEmpty ? nil : note
                )
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
            }
            sending = false
        }
    }
}
