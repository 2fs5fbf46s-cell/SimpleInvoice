//
//  NewClientSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Adds a client without leaving the form that needed one.
///
/// The New Estimate and New Invoice sheets could only pick from existing
/// clients, so a first-time customer meant cancelling, going to Clients,
/// adding them, and starting the estimate over. This presents the same
/// editor the Clients tab uses and hands the saved client back.
struct NewClientSheet: View {
    @Environment(\.modelContext) private var modelContext

    let draft: Client
    /// The saved client, or an existing one the owner chose instead after a
    /// duplicate warning. Nil when they cancelled.
    let onFinish: (Client?) -> Void

    @State private var saveError: String? = nil

    var body: some View {
        NavigationStack {
            ClientEditView(
                client: draft,
                isDraft: true,
                onOpenExisting: { existing in
                    discardDraft()
                    onFinish(existing)
                }
            )
            .navigationTitle("New Client")
            .navigationBarTitleDisplayMode(.inline)
            .sbwNavigationBarBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discardDraft()
                        onFinish(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        }
        .interactiveDismissDisabled()
    }

    /// Inserts an empty client for `businessID`. It's inserted up front, like
    /// the Clients tab does, so Contacts import and edits are tracked.
    static func makeDraft(businessID: UUID, in context: ModelContext) -> Client {
        let client = Client(businessID: businessID)
        context.insert(client)
        try? context.save()
        return client
    }

    private func save() {
        do {
            try modelContext.save()
            onFinish(draft)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Cancel means cancel here, even with fields typed in: the owner came
    /// to pick a client for this estimate, not to file one away.
    private func discardDraft() {
        modelContext.delete(draft)
        try? modelContext.save()
    }
}
