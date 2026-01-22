import SwiftUI
import SwiftData

struct JobAttachmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (FileItem) -> Void

    @State private var searchText: String = ""

    @Query(sort: [SortDescriptor(\FileItem.createdAt, order: .reverse)])
    private var allFiles: [FileItem]

    private var filtered: [FileItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return allFiles }
        return allFiles.filter {
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
                        description: Text("Import files first, then attach them to jobs.")
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
