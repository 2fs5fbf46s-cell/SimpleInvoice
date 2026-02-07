import SwiftUI

struct FolderRowView: View {
    let business: Business
    let folder: Folder
    let isEditing: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                SBWNavigationRow(
                    title: folder.name.isEmpty ? "Folder" : folder.name,
                    subtitle: folder.relativePath
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
        .opacity(isEditing ? 0.75 : 1)
    }
}
