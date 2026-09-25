//
//  BusinessSwitcherView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import OSLog
import SwiftUI
import SwiftData

struct BusinessSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query private var businesses: [Business]
    @Query private var profiles: [BusinessProfile]

    // Cascade-delete used to keep a live @Query over all fourteen of these tables,
    // which meant this list view held every record in the database for as long as
    // it was on screen — to support an action that usually never runs. The records
    // are now fetched, scoped to the business, at the moment of deletion.

    @State private var newBusinessName: String = ""

    @State private var pendingDelete: Business? = nil
    @State private var showCannotDeleteAlert = false

    @State private var pendingRename: Business? = nil
    @State private var renameBusinessName: String = ""

    var body: some View {
        Form {
            Section("Active Business") {
                if let id = activeBiz.activeBusinessID,
                   let active = businesses.first(where: { $0.id == id }) {
                    Text(active.name).font(.headline)
                } else {
                    Text("None selected").foregroundStyle(.secondary)
                }
            }

            Section("Businesses") {
                if businesses.isEmpty {
                    Text("No businesses yet").foregroundStyle(.secondary)
                } else {
                    ForEach(businesses) { b in
                        businessRow(b)
                    }
                }
            }

            Section("Add Business") {
                TextField("Business name", text: $newBusinessName)
                Button("Create") {
                    let name = newBusinessName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }

                    let created = Business(name: name, isActive: true)
                    modelContext.insert(created)
                    try? modelContext.save()

                    activeBiz.setActiveBusiness(created.id)
                    newBusinessName = ""
                }
            }
        }
        .navigationTitle("Businesses")
        .onAppear {
            try? activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        }
        .alert("You must keep at least one business.", isPresented: $showCannotDeleteAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("Delete Business?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    deleteBusiness(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This will delete all data for this business.")
        }
        .alert("Rename Business", isPresented: Binding(
            get: { pendingRename != nil },
            set: { if !$0 { pendingRename = nil } }
        )) {
            TextField("Business name", text: $renameBusinessName)

            Button("Cancel", role: .cancel) {
                pendingRename = nil
            }

            Button("Save") {
                if let biz = pendingRename {
                    renameBusiness(biz, newName: renameBusinessName)
                }
                pendingRename = nil
            }
        } message: {
            Text("This updates the business name across the app.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func businessRow(_ b: Business) -> some View {
        let isActive = (b.id == activeBiz.activeBusinessID)

        Button {
            activeBiz.setActiveBusiness(b.id)
        } label: {
            HStack {
                Text(b.name)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                pendingRename = b
                renameBusinessName = b.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                requestDelete(b)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Rename

    private func renameBusiness(_ business: Business, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // One rename for the switcher, documents, booking page and website.
        if let profile = profiles.first(where: { $0.businessID == business.id }) {
            BusinessIdentity.rename(profile: profile, business: business, to: trimmed, context: modelContext)
            return
        }
        business.name = trimmed

        do {
            try modelContext.save()
        } catch {
            SBWLog.ui.problem("Failed to rename business: \(error)")
        }
    }

    // MARK: - Deletion

    private func requestDelete(_ business: Business) {
        guard businesses.count > 1 else {
            showCannotDeleteAlert = true
            return
        }
        pendingDelete = business
    }

    private func deleteBusiness(_ business: Business) {
        let businessID = business.id

        if activeBiz.activeBusinessID == businessID {
            if let replacement = businesses.first(where: { $0.id != businessID }) {
                activeBiz.setActiveBusiness(replacement.id)
            } else {
                activeBiz.clearActiveBusiness()
            }
        }

        deleteAll(BusinessProfile.self, #Predicate { $0.businessID == businessID })
        deleteAll(Client.self, #Predicate { $0.businessID == businessID })
        deleteAll(Invoice.self, #Predicate { $0.businessID == businessID })
        deleteAll(Job.self, #Predicate { $0.businessID == businessID })
        deleteAll(Contract.self, #Predicate { $0.businessID == businessID })
        deleteAll(ContractSignature.self, #Predicate { $0.businessID == businessID })
        deleteAll(CatalogItem.self, #Predicate { $0.businessID == businessID })
        deleteAll(Attachment.self, #Predicate { $0.businessID == businessID })
        deleteAll(Folder.self, #Predicate { $0.businessID == businessID })
        deleteAll(Blockout.self, #Predicate { $0.businessID == businessID })
        deleteAll(AuditEvent.self, #Predicate { $0.businessID == businessID })
        deleteAll(PortalIdentity.self, #Predicate { $0.businessID == businessID })
        deleteAll(PortalInvite.self, #Predicate { $0.businessID == businessID })
        deleteAll(PortalSession.self, #Predicate { $0.businessID == businessID })
        deleteAll(PortalAuditEvent.self, #Predicate { $0.businessID == businessID })

        modelContext.delete(business)

        do {
            try modelContext.save()
        } catch {
            SBWLog.ui.problem("Failed to delete business: \(error)")
        }
    }

    /// Fetch just this business's rows of one type and delete them.
    ///
    /// Deletes each object individually rather than using a bulk delete, so
    /// SwiftData's relationship delete rules fire exactly as they did when these
    /// were driven off live queries.
    private func deleteAll<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) {
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items { modelContext.delete(item) }
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// No inputs: queries and state drive every update.
extension BusinessSwitcherView: Equatable {
    static func == (_: BusinessSwitcherView, _: BusinessSwitcherView) -> Bool {
        true
    }
}
