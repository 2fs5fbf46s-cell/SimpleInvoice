//
//  BusinessSwitcherView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftUI
import SwiftData

struct BusinessSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var businesses: [Business]
    @Query private var profiles: [BusinessProfile]
    @Query private var clients: [Client]
    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var contracts: [Contract]
    @Query private var contractSignatures: [ContractSignature]
    @Query private var catalogItems: [CatalogItem]
    @Query private var attachments: [Attachment]
    @Query private var folders: [Folder]
    @Query private var blockouts: [Blockout]
    @Query private var auditEvents: [AuditEvent]
    @Query private var portalIdentities: [PortalIdentity]
    @Query private var portalInvites: [PortalInvite]
    @Query private var portalSessions: [PortalSession]
    @Query private var portalAuditEvents: [PortalAuditEvent]

    @State private var newBusinessName: String = ""
    @State private var pendingDelete: Business? = nil
    @State private var showCannotDeleteAlert = false

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
                        Button {
                            activeBiz.setActiveBusiness(b.id)
                        } label: {
                            HStack {
                                Text(b.name)
                                Spacer()
                                if b.id == activeBiz.activeBusinessID {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                requestDelete(b)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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

        deleteItems(profiles.filter { $0.businessID == businessID })
        deleteItems(clients.filter { $0.businessID == businessID })
        deleteItems(invoices.filter { $0.businessID == businessID })
        deleteItems(jobs.filter { $0.businessID == businessID })
        deleteItems(contracts.filter { $0.businessID == businessID })
        deleteItems(contractSignatures.filter { $0.businessID == businessID })
        deleteItems(catalogItems.filter { $0.businessID == businessID })
        deleteItems(attachments.filter { $0.businessID == businessID })
        deleteItems(folders.filter { $0.businessID == businessID })
        deleteItems(blockouts.filter { $0.businessID == businessID })
        deleteItems(auditEvents.filter { $0.businessID == businessID })
        deleteItems(portalIdentities.filter { $0.businessID == businessID })
        deleteItems(portalInvites.filter { $0.businessID == businessID })
        deleteItems(portalSessions.filter { $0.businessID == businessID })
        deleteItems(portalAuditEvents.filter { $0.businessID == businessID })

        modelContext.delete(business)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete business: \(error)")
        }
    }

    private func deleteItems<T: PersistentModel>(_ items: [T]) {
        for item in items { modelContext.delete(item) }
    }
}
