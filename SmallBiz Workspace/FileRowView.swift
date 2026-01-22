import SwiftUI

struct FileRowView: View {
    let item: FileItem
    let icon: String
    let isEditing: Bool

    let onOpen: () -> Void
    let onZip: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            if !isEditing { onOpen() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName.isEmpty ? "File" : item.displayName)
                        .lineLimit(1)

                    Text(item.originalFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "doc")
            }

            Button {
                onZip()
            } label: {
                Label("ZIP", systemImage: "doc.zipper")
            }

            Button {
                onMove()
            } label: {
                Label("Move…", systemImage: "folder")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onMove()
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(.blue)
        }
    }
}
