import Foundation
import SwiftData

enum FolderZipExporter {

    // ZIP current folder (all files in folder + recursively in subfolders)
    static func exportFolderZip(businessID: UUID, folder: Folder, context: ModelContext) throws -> URL {
        let urls = try gatherFileURLsRecursively(businessID: businessID, folderID: folder.id, context: context)
        let zipBase = "\(folder.name)-Folder"
        return try AttachmentZipExporter.zipFiles(urls, zipName: zipBase)
    }

    // ZIP selection (files + folders). Folders are recursive.
    static func exportSelectionZip(
        businessID: UUID,
        currentFolder: Folder,
        selectedFiles: [FileItem],
        selectedFolders: [Folder],
        context: ModelContext
    ) throws -> URL {
        var urls: [URL] = []

        // selected files
        for f in selectedFiles {
            if let u = try? AppFileStore.absoluteURL(forRelativePath: f.relativePath) {
                urls.append(u)
            }
        }

        // selected folders (recursive)
        for folder in selectedFolders {
            let folderURLs = try gatherFileURLsRecursively(businessID: businessID, folderID: folder.id, context: context)
            urls.append(contentsOf: folderURLs)
        }

        // de-dupe
        urls = Array(Set(urls))

        let zipBase = "\(currentFolder.name)-Selection"
        return try AttachmentZipExporter.zipFiles(urls, zipName: zipBase)
    }

    // ZIP explicit list of files (non-recursive)
    static func exportFilesZip(_ files: [FileItem], zipBaseName: String, context: ModelContext) throws -> URL {
        let urls: [URL] = files.compactMap { try? AppFileStore.absoluteURL(forRelativePath: $0.relativePath) }
        return try AttachmentZipExporter.zipFiles(urls, zipName: zipBaseName)
    }

    // ZIP explicit list of folders (recursive)
    static func exportFoldersZip(businessID: UUID, folders: [Folder], zipBaseName: String, context: ModelContext) throws -> URL {
        var urls: [URL] = []
        for f in folders {
            let folderURLs = try gatherFileURLsRecursively(businessID: businessID, folderID: f.id, context: context)
            urls.append(contentsOf: folderURLs)
        }
        urls = Array(Set(urls))
        return try AttachmentZipExporter.zipFiles(urls, zipName: zipBaseName)
    }

    // MARK: - Recursive gather

    private static func gatherFileURLsRecursively(businessID: UUID, folderID: UUID, context: ModelContext) throws -> [URL] {
        var urls: [URL] = []

        // files in this folder
        let folderKey = folderID.uuidString
        let filesDesc = FetchDescriptor<FileItem>(
            predicate: #Predicate { item in
                item.folderKey == folderKey
            }
        )
        let files = try context.fetch(filesDesc)

        for f in files {
            if let u = try? AppFileStore.absoluteURL(forRelativePath: f.relativePath) {
                urls.append(u)
            }
        }

        // child folders
        let foldersDesc = FetchDescriptor<Folder>(
            predicate: #Predicate { fo in
                fo.businessID == businessID &&
                fo.parentFolderID == folderID
            }
        )
        let kids = try context.fetch(foldersDesc)

        for child in kids {
            let childURLs = try gatherFileURLsRecursively(businessID: businessID, folderID: child.id, context: context)
            urls.append(contentsOf: childURLs)
        }

        return urls
    }
}
