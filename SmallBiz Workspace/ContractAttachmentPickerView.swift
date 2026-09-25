//
//  ContractAttachmentPickerView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/16/26.
//

import Foundation
import SwiftUI
import SwiftData

struct ContractAttachmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    /// Only this business's files; nil lists everything (older callers).
    var businessID: UUID? = nil
    let onPick: (FileItem) -> Void

    @State private var searchText: String = ""

    @Query(sort: [SortDescriptor(\FileItem.createdAt, order: .reverse)])
    private var allFiles: [FileItem]

    var filtered: [FileItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scoped = businessID.map { id in allFiles.filter { $0.folder?.businessID == id } } ?? allFiles
        if q.isEmpty { return scoped }
        return scoped.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.originalFileName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No files found",
                        systemImage: "doc",
                        description: Text("Import files first, then attach them to contracts.")
                    )
                } else {
                    ForEach(filtered) { file in
                        Button {
                            onPick(file)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.displayName)
                                Text(file.originalFileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick a File")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
