//
//  JobExportToFilesService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

enum ExportConflictAction {
    case overwrite
    case saveCopy
}

struct JobExportToFilesService {

    // MARK: - Public

    static func resolveJobSubfolder(
        job: Job,
        named folderName: String,
        context: ModelContext
    ) throws -> Folder {
        let lower = folderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let kind = JobWorkspaceSubfolder(rawValue: lower) {
            return try WorkspaceProvisioningService.fetchJobSubfolder(
                job: job,
                kind: kind,
                context: context
            )
        }

        // Fallback: explicit relative path under job root (non-standard folder)
        let root = try WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: context)
        let rel = makeChildRelativePath(parent: root, childName: folderName)
        if let existing = try FolderService.fetchFolder(
            businessID: root.businessID,
            relativePath: rel,
            context: context
        ) {
            return existing
        }

        let newFolder = Folder(
            businessID: root.businessID,
            name: folderName,
            relativePath: rel,
            parentFolderID: root.id
        )
        context.insert(newFolder)
        try context.save()
        return newFolder
    }

    /// Saves a PDF into a specific Folder by creating a FileItem record.
    /// - If conflictAction is provided and an existing FileItem is passed, we overwrite or save-copy.
    static func savePDF(
        data: Data,
        preferredFileNameWithExtension: String, // e.g., "Invoice-123.pdf"
        into folder: Folder,
        existingMatch: FileItem?,
        conflictAction: ExportConflictAction?,
        context: ModelContext
    ) throws -> FileItem {

        let finalName: String
        if let existingMatch, let conflictAction {
            switch conflictAction {
            case .overwrite:
                // remove old disk file + record
                try? AppFileStore.deleteFile(for: existingMatch)
                context.delete(existingMatch)
                finalName = preferredFileNameWithExtension
            case .saveCopy:
                finalName = makeCopyName(preferredFileNameWithExtension, in: folder, context: context)
            }
        } else {
            finalName = preferredFileNameWithExtension
        }

        let fileId = UUID()
        let (rel, size) = try AppFileStore.importData(data, fileId: fileId, preferredFileName: finalName)

        let ext = (finalName as NSString).pathExtension.lowercased()
        let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"

        let item = FileItem(
            displayName: finalName.replacingOccurrences(of: ".\(ext)", with: ""),
            originalFileName: finalName,
            relativePath: rel,
            fileExtension: ext,
            uti: uti,
            byteCount: size,
            folderKey: folder.id.uuidString,
            folder: folder
        )
        context.insert(item)
        try context.save()
        return item
    }

    // MARK: - Helpers

    // Same logic used in FolderBrowserView.makeChildRelativePath【turn11file15†L26-L31】
    private static func makeChildRelativePath(parent: Folder, childName: String) -> String {
        let p = parent.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let c = childName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if p.isEmpty { return c }
        return "\(p)/\(c)"
    }

    private static func makeCopyName(_ name: String, in folder: Folder, context: ModelContext) -> String {
        // checks existing FileItems in that folderKey
        let folderKey = folder.id.uuidString

        // Fetch ALL FileItems is fine here; you already do in-memory filtering elsewhere
        let d = FetchDescriptor<FileItem>()
        let all = (try? context.fetch(d)) ?? []
        let existingNames = Set(all.filter { $0.folderKey == folderKey }.map { $0.originalFileName })

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if !existingNames.contains(name) { return name }

        var i = 1
        while true {
            let candidate = "\(base) (\(i)).\(ext)"
            if !existingNames.contains(candidate) { return candidate }
            i += 1
        }
    }
}
