import Foundation
import SwiftData

enum JobWorkspaceSubfolder: String, CaseIterable {
    case contracts
    case invoices
    case media
    case deliverables
    case reference

    var displayName: String {
        switch self {
        case .contracts: return "Contracts"
        case .invoices: return "Invoices"
        case .media: return "Media"
        case .deliverables: return "Deliverables"
        case .reference: return "Reference"
        }
    }
}

enum WorkspaceProvisioningService {

    private struct JobWorkspacePaths {
        let jobRoot: String
        let subfolders: [JobWorkspaceSubfolder: String]
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func makeJobWorkspacePaths(job: Job, root: Folder) -> JobWorkspacePaths {
        let rootRel = normalizedPath(root.relativePath)
        let jobsRoot = rootRel.isEmpty ? "jobs" : "\(rootRel)/jobs"
        let jobRoot = "\(jobsRoot)/\(job.id.uuidString)"

        var subfolders: [JobWorkspaceSubfolder: String] = [:]
        for kind in JobWorkspaceSubfolder.allCases {
            subfolders[kind] = "\(jobRoot)/\(kind.rawValue)"
        }
        return JobWorkspacePaths(jobRoot: jobRoot, subfolders: subfolders)
    }

    private static func jobFolderDisplayName(for job: Job) -> String {
        let trimmedTitle = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Project" : trimmedTitle
    }

    private static func upsertFolder(
        businessID: UUID,
        relativePath: String,
        name: String,
        parentID: UUID?,
        context: ModelContext
    ) throws -> Folder {
        if let existing = try FolderService.fetchFolder(
            businessID: businessID,
            relativePath: relativePath,
            context: context
        ) {
            var didChange = false
            if existing.parentFolderID != parentID {
                existing.parentFolderID = parentID
                didChange = true
            }
            if existing.name != name {
                existing.name = name
                didChange = true
            }
            if didChange {
                existing.updatedAt = .now
                try context.save()
            }
            return existing
        }

        let folder = Folder(
            businessID: businessID,
            name: name,
            relativePath: relativePath,
            parentFolderID: parentID
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    /// Creates the Job workspace folder (and default subfolders) if it doesn't exist.
    /// Idempotent by businessID + relativePath.
    static func ensureJobWorkspace(
        job: Job,
        context: ModelContext
    ) throws -> Folder {

        let businessID = job.businessID
        try FolderService.bootstrapRootIfNeeded(businessID: businessID, context: context)

        guard let root = try FolderService.fetchRootFolder(
            businessID: businessID,
            context: context
        ) else {
            throw NSError(domain: "Workspace", code: 404)
        }

        let paths = makeJobWorkspacePaths(job: job, root: root)
        let displayName = jobFolderDisplayName(for: job)

        let jobFolder: Folder
        if let existing = try FolderService.fetchFolder(
            businessID: businessID,
            relativePath: paths.jobRoot,
            context: context
        ) {
            if existing.parentFolderID != root.id || existing.name != displayName {
                existing.parentFolderID = root.id
                existing.name = displayName
                existing.updatedAt = .now
                try context.save()
            }
            jobFolder = existing
        } else if
            let key = job.workspaceFolderKey,
            let folderID = UUID(uuidString: key),
            let existing = try context.fetch(
                FetchDescriptor<Folder>(
                    predicate: #Predicate { $0.id == folderID }
                )
            ).first
        {
            existing.relativePath = paths.jobRoot
            existing.parentFolderID = root.id
            existing.name = displayName
            existing.updatedAt = .now
            try context.save()
            jobFolder = existing
        } else {
            jobFolder = try upsertFolder(
                businessID: businessID,
                relativePath: paths.jobRoot,
                name: displayName,
                parentID: root.id,
                context: context
            )
        }

        for (kind, rel) in paths.subfolders {
            _ = try upsertFolder(
                businessID: businessID,
                relativePath: rel,
                name: kind.displayName,
                parentID: jobFolder.id,
                context: context
            )
        }

        job.workspaceFolderKey = jobFolder.id.uuidString
        try context.save()
        return jobFolder
    }

    static func fetchJobSubfolder(
        job: Job,
        kind: JobWorkspaceSubfolder,
        context: ModelContext
    ) throws -> Folder {
        let jobFolder = try ensureJobWorkspace(job: job, context: context)
        let base = normalizedPath(jobFolder.relativePath)
        let rel = base.isEmpty ? kind.rawValue : "\(base)/\(kind.rawValue)"

        if let existing = try FolderService.fetchFolder(
            businessID: job.businessID,
            relativePath: rel,
            context: context
        ) {
            if existing.parentFolderID != jobFolder.id || existing.name != kind.displayName {
                existing.parentFolderID = jobFolder.id
                existing.name = kind.displayName
                existing.updatedAt = .now
                try context.save()
            }
            return existing
        }

        let folder = Folder(
            businessID: job.businessID,
            name: kind.displayName,
            relativePath: rel,
            parentFolderID: jobFolder.id
        )
        context.insert(folder)
        try context.save()
        return folder
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

        folder.name = trimmedTitle
        folder.updatedAt = .now
        try context.save()
    }
}
