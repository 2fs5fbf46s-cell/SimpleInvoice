import Foundation
import UniformTypeIdentifiers

struct AttachmentStorageResult {
    let file: FileItem
}

enum AttachmentStorage {
    static func importFile(
        from sourceURL: URL,
        businessID: UUID,
        entityType: String,
        entityKey: String
    ) throws -> AttachmentStorageResult {
        let fileID = UUID()
        let originalName = sourceURL.lastPathComponent
        let folderPath = "attachments/\(businessID.uuidString)/\(entityType)/\(entityKey)"
        let preferredName = "\(fileID.uuidString)-\(sanitizeFileName(originalName))"

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let imported = try AppFileStore.importFile(
            from: sourceURL,
            toRelativeFolderPath: folderPath,
            preferredFileName: preferredName
        )

        let ext = sourceURL.pathExtension.lowercased()
        let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"
        let displayName = sourceURL.deletingPathExtension().lastPathComponent

        let file = FileItem(
            displayName: displayName.isEmpty ? originalName : displayName,
            originalFileName: originalName,
            relativePath: imported.0,
            fileExtension: ext,
            uti: uti,
            byteCount: imported.1,
            folderKey: "attachments:\(entityType):\(entityKey)"
        )
        return AttachmentStorageResult(file: file)
    }

    static func bestEffortDelete(_ file: FileItem) {
        do {
            try AppFileStore.deleteFile(for: file)
        } catch {
            print("Attachment file delete failed: \(error)")
        }
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "file" : cleaned
    }

}
