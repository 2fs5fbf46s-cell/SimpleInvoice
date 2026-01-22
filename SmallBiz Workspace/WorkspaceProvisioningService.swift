import Foundation
import SwiftData

enum WorkspaceProvisioningService {

    /// Creates the Job workspace folder (and default subfolders) if it doesn't exist.
    /// If the Job already has a workspace folder, this simply returns it.
    ///
    /// If the job title is empty, the folder will be created as "Project".
    /// When a title is later added/changed, call `syncJobWorkspaceName(job:context:)`.

    static func ensureJobWorkspace(
        job: Job,
        context: ModelContext
    ) throws -> Folder {

        if
            let key = job.workspaceFolderKey,
            let folderID = UUID(uuidString: key),
            let existing = try context.fetch(
                FetchDescriptor<Folder>(
                    predicate: #Predicate { $0.id == folderID }
                )
            ).first
        {
            return existing
        }

        let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: context)
        try FolderService.bootstrapRootIfNeeded(businessID: biz.id, context: context)

        guard let root = try FolderService.fetchRootFolder(
            businessID: biz.id,
            context: context
        ) else {
            throw NSError(domain: "Workspace", code: 404)
        }

        let trimmedTitle = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedTitle.isEmpty ? "Project" : trimmedTitle

        try FolderService.createFolder(
            businessID: biz.id,
            name: name,
            parent: root,
            context: context
        )

        let children = try FolderService.fetchChildren(
            businessID: biz.id,
            parentID: root.id,
            context: context
        )

        guard let jobFolder = children
            .filter({ $0.name == name })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first
        else {
            throw NSError(domain: "Workspace", code: 500)
        }

        for sub in ["Contracts", "Invoices", "Media", "Deliverables", "Reference"] {
            try FolderService.createFolder(
                businessID: biz.id,
                name: sub,
                parent: jobFolder,
                context: context
            )
        }

        job.workspaceFolderKey = jobFolder.id.uuidString
        try context.save()
        return jobFolder
    }

    /// If a Job already has a workspace folder, keep its folder name in sync with the Job title.
    /// Safe to call often; it no-ops when there's nothing to do.
    static func syncJobWorkspaceName(job: Job, context: ModelContext) throws {
        guard
            let key = job.workspaceFolderKey,
            let folderID = UUID(uuidString: key),
            let folder = try context.fetch(
                FetchDescriptor<Folder>(predicate: #Predicate { $0.id == folderID })
            ).first
        else {
            return
        }

        let trimmedTitle = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard folder.name != trimmedTitle else { return }

        try FolderService.renameFolder(folder: folder, newName: trimmedTitle, context: context)
    }
    
}
