//
//  CreateFolderView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import SwiftUI
import SwiftData

struct CreateFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let business: Business
    let parent: Folder

    @State private var name: String = ""

    var body: some View {
        Form {
            Section("Folder name") {
                TextField("e.g. Receipts", text: $name)
            }
            Button("Create") { create() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .navigationTitle("New Folder")
    }

    private func create() {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return }

        let rel = parent.relativePath.isEmpty ? safeName : "\(parent.relativePath)/\(safeName)"

        do {
            try FileStore.shared.createFolder(relativePath: rel)
            let folder = Folder(
                businessID: business.id,
                name: safeName,
                relativePath: rel,
                parentFolderID: parent.id
            )
            modelContext.insert(folder)

            AuditLogger.shared.log(
                modelContext: modelContext,
                businessID: business.id,
                entityType: "Folder",
                entityID: folder.id,
                action: .create,
                summary: "Created folder \(folder.name)"
            )
            try modelContext.save()
            dismiss()
        } catch {
            // add alert later
        }
    }
}
