//
//  ClientEditView.swift
//  SmallBiz Workspace
//

import Foundation
import OSLog
import SwiftUI
import SwiftData
import UIKit
import Contacts
import ContactsUI

/// The client's contact details and private notes: the form behind New
/// Client and the client screen's Edit button.
///
/// It used to also hold the portal switch, the invoice template, the job
/// list, the files and an Advanced section, and it was where the Clients
/// tab's Done and a house button lived. Those are on the client screen
/// (ClientDetailView) now; this is only the form. Callers put it in a
/// NavigationStack and supply Done/Cancel.
struct ClientEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var client: Client
    let isDraft: Bool
    /// Called when a Contacts import matches a client that already exists
    /// and the owner chooses to open that one instead.
    let onOpenExisting: ((Client) -> Void)?

    @State private var pendingSaveTask: Task<Void, Never>? = nil
    @State private var saveError: String? = nil

    @State private var showingContactPicker = false
    @State private var suppressAutoSave = false
    @State private var showContactImportBanner = false
    @State private var contactImportError: String? = nil
    @State private var pendingContact: CNContact? = nil
    @State private var duplicateCandidate: Client? = nil
    @State private var showDuplicateDialog = false
    @State private var contactAccessDenied = false

    @Query private var businessClients: [Client]

    init(client: Client, isDraft: Bool = false, onOpenExisting: ((Client) -> Void)? = nil) {
        self.client = client
        self.isDraft = isDraft
        self.onOpenExisting = onOpenExisting

        let businessID = client.businessID
        self._businessClients = Query(
            filter: #Predicate<Client> { c in
                c.businessID == businessID
            },
            sort: [SortDescriptor(\.name, order: .forward)]
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $client.name)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .onChange(of: client.name) { _, _ in scheduleSave() }

                TextField("Email", text: $client.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .onChange(of: client.email) { _, _ in scheduleSave() }

                TextField("Phone", text: $client.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .onChange(of: client.phone) { _, _ in scheduleSave() }
            } header: {
                Text("Contact")
            } footer: {
                Text("Invoices and estimates are emailed to this address.")
            }

            Section {
                Button {
                    attemptContactImport()
                } label: {
                    Label("Fill from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
                if contactAccessDenied {
                    Text("Allow SmallBiz Workspace to use Contacts in Settings to fill from a contact.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Address") {
                TextField("Street, city, state, ZIP", text: $client.address, axis: .vertical)
                    .lineLimit(2...5)
                    .textContentType(.fullStreetAddress)
                    .onChange(of: client.address) { _, _ in scheduleSave() }
            }

            Section {
                leadSourceChips
            } header: {
                Text("How Did They Hear About You?")
            } footer: {
                Text("Optional — helps you see what's actually bringing in work, in Insights.")
            }

            Section {
                TextField("Gate codes, preferences, anything to remember", text: $client.notes, axis: .vertical)
                    .lineLimit(3...10)
                    .onChange(of: client.notes) { _, _ in scheduleSave() }
            } header: {
                Text("Notes")
            } footer: {
                Text("Only you see these. They're never sent to the client.")
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPicker(isPresented: $showingContactPicker) { contact in
                handleContactSelection(contact)
            } onCancel: {
            }
        }
        .alert("Couldn’t Save Client", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .alert("Couldn’t Fill from Contacts", isPresented: Binding(
            get: { contactImportError != nil },
            set: { if !$0 { contactImportError = nil } }
        )) {
            Button("OK", role: .cancel) { contactImportError = nil }
        } message: {
            Text(contactImportError ?? "")
        }
        .confirmationDialog(
            "You already have this client",
            isPresented: $showDuplicateDialog,
            presenting: duplicateCandidate
        ) { match in
            if let onOpenExisting {
                Button("Open \(match.displayName)") {
                    onOpenExisting(match)
                    pendingContact = nil
                    duplicateCandidate = nil
                }
            }
            Button("Use This Contact Anyway") {
                if let contact = pendingContact {
                    applyContactToClient(contact)
                }
                pendingContact = nil
                duplicateCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                pendingContact = nil
                duplicateCandidate = nil
            }
        } message: { match in
            Text("\(match.displayName) has the same email or phone.")
        }
        .overlay(alignment: .top) {
            if showContactImportBanner {
                ContactImportBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { refreshContactsPermissionState() }
        .onDisappear {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            // Flush the last keystrokes of an existing client; a draft is
            // saved or thrown away by whoever presented it.
            if !isDraft { try? modelContext.save() }
        }
    }

    // MARK: - Lead source

    private var leadSourceChips: some View {
        // A flow layout would be nicer than a fixed grid, but five short
        // labels fit two-per-row at every Dynamic Type size this app
        // supports, and this mirrors the grid WrapRow already used
        // elsewhere (SavedItemsView's category filter) without pulling in
        // its UIHostingController-measuring machinery for five static chips.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(LeadSource.allCases) { source in
                Button {
                    client.leadSource = (client.leadSource == source) ? nil : source
                    scheduleSave()
                } label: {
                    Text(source.displayName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(client.leadSource == source ? SBWTheme.brandTint : Color(.secondarySystemFill))
                        )
                        .foregroundStyle(client.leadSource == source ? SBWTheme.brand : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(client.leadSource == source ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Save

    private func scheduleSave() {
        if isDraft || suppressAutoSave { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                try modelContext.save()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    // MARK: - Contacts

    private func refreshContactsPermissionState() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        contactAccessDenied = (status == .denied || status == .restricted)
    }

    private func attemptContactImport() {
        refreshContactsPermissionState()
        guard !contactAccessDenied else { return }
        showingContactPicker = true
    }

    private func handleContactSelection(_ contact: CNContact) {
        let fields = ContactImportMapper.fields(from: contact)
        if let match = ContactImportMapper.findDuplicateClient(
            in: businessClients,
            fields: fields,
            businessID: client.businessID
        ), match.persistentModelID != client.persistentModelID {
            pendingContact = contact
            duplicateCandidate = match
            showDuplicateDialog = true
            return
        }
        applyContactToClient(contact)
    }

    /// Fills the form and stays on it. It used to close the screen 0.6
    /// seconds later, before there was any chance to check what came in.
    private func applyContactToClient(_ contact: CNContact) {
        suppressAutoSave = true
        ContactImportMapper.apply(contact: contact, to: client)
        if !isDraft {
            do {
                try modelContext.save()
            } catch {
                contactImportError = error.localizedDescription
            }
        }
        Haptics.lightTap()
        withAnimation(.easeOut(duration: 0.18)) { showContactImportBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.18)) { showContactImportBanner = false }
        }
        DispatchQueue.main.async { suppressAutoSave = false }
    }
}

private struct ContactImportBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SBWTheme.success)
            Text("Filled from Contacts")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().stroke(SBWTheme.cardStroke, lineWidth: 1))
        )
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

/// The client screen's Edit button: the form, with Done.
struct ClientEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let client: Client

    var body: some View {
        NavigationStack {
            ClientEditView(client: client)
                .navigationTitle("Edit Client")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            try? modelContext.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// Compared by what it shows; callbacks and bindings are ignored.
extension ClientEditView: Equatable {
    static func == (lhs: ClientEditView, rhs: ClientEditView) -> Bool {
        lhs.client.persistentModelID == rhs.client.persistentModelID
            && lhs.isDraft == rhs.isDraft
    }
}
