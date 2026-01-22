import SwiftUI

struct FolderRowView: View {
    let business: Business
    let folder: Folder
    let isEditing: Bool

    var body: some View {
        NavigationLink {
            FolderBrowserView(business: business, folder: folder)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name.isEmpty ? "Folder" : folder.name)
                        .lineLimit(1)

                    Text(folder.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isEditing {
                    // In edit mode, NavigationLink still works, but visually less noisy
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(0.4)
                }
            }
        }
    }
}
