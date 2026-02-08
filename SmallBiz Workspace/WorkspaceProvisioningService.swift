import Foundation
import SwiftData

enum FolderDestinationKind: String, CaseIterable {
    case invoices
    case estimates
    case contracts
    case photos
    case attachments
    case deliverables
    case other

    var displayName: String {
        switch self {
        case .invoices: return "Invoices"
        case .estimates: return "Estimates"
        case .contracts: return "Contracts"
        case .photos: return "Photos"
        case .attachments: return "Attachments"
        case .deliverables: return "Deliverables"
        case .other: return "Other"
        }
    }

    var jobSubfolderKind: JobWorkspaceSubfolder {
        switch self {
        case .invoices: return .invoices
        case .estimates: return .estimates
        case .contracts: return .contracts
        case .photos: return .photos
        case .attachments: return .attachments
        case .deliverables: return .deliverables
        case .other: return .other
        }
    }
}

enum JobWorkspaceSubfolder: String, CaseIterable {
    case contracts
    case invoices
    case estimates
    case photos
    case attachments
    case deliverables
    case audio
    case notes
    case other

    var displayName: String {
        switch self {
        case .contracts: return "Contracts"
        case .invoices: return "Invoices"
        case .estimates: return "Estimates"
        case .photos: return "Photos"
        case .attachments: return "Attachments"
        case .deliverables: return "Deliverables"
        case .audio: return "Audio"
        case .notes: return "Notes"
        case .other: return "Other"
        }
    }

    static func from(folderName: String) -> JobWorkspaceSubfolder? {
        let lower = folderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "contracts": return .contracts
        case "invoices": return .invoices
        case "estimates": return .estimates
        case "photos", "pictures", "media": return .photos
        case "attachments": return .attachments
        case "deliverables": return .deliverables
        case "audio": return .audio
        case "notes": return .notes
        case "other", "reference": return .other
        default: return nil
        }
    }
}

enum WorkspaceProvisioningService {

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func pathAppending(_ base: String, _ component: String) -> String {
        let left = normalizedPath(base)
        let right = normalizedPath(component)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return "\(left)/\(right)"
    }

    private static func keyForClient(_ clientID: UUID) -> String {
        "client:\(clientID.uuidString)"
    }

    private static func keyForJob(_ jobID: UUID) -> String {
        "job:\(jobID.uuidString)"
    }

    private static func keyForJobSubfolder(_ jobID: UUID, kind: JobWorkspaceSubfolder) -> String {
        "job:\(jobID.uuidString):\(kind.rawValue)"
    }

    private static func keyForClientSubfolder(_ clientID: UUID, kind: FolderDestinationKind) -> String {
        "client:\(clientID.uuidString):\(kind.rawValue)"
    }

    private static func keyForUnsorted(_ businessID: UUID) -> String {
        "unsorted:\(businessID.uuidString)"
    }

    private static func keyForUnsortedSubfolder(_ businessID: UUID, kind: FolderDestinationKind) -> String {
        "unsorted:\(businessID.uuidString):\(kind.rawValue)"
    }

    private static func clientFolderDisplayName(for client: Client) -> String {
        let trimmed = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client \(client.id.uuidString.prefix(8))" : trimmed
    }

    private static func jobFolderDisplayName(for job: Job) -> String {
        let trimmed = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Job \(job.id.uuidString.prefix(8))" : trimmed
    }

    private static func fetchClient(for job: Job, context: ModelContext) throws -> Client? {
        guard let clientID = job.clientID else { return nil }
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { client in
                client.id == clientID
            }
        )
        return try context.fetch(descriptor).first
    }

    private static func upsertFolder(
        businessID: UUID,
        folderKey: String,
        relativePath: String,
        name: String,
        parentID: UUID?,
        context: ModelContext
    ) throws -> Folder {
        let normalizedRelativePath = normalizedPath(relativePath)

        if let existing = try FolderService.fetchFolder(
            businessID: businessID,
            folderKey: folderKey,
            context: context
        ) {
            var didChange = false
            if existing.relativePath != normalizedRelativePath {
                existing.relativePath = normalizedRelativePath
                didChange = true
            }
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

        // Adopt a legacy folder at the same path when possible.
        if let existingAtPath = try FolderService.fetchFolder(
            businessID: businessID,
            relativePath: normalizedRelativePath,
            context: context
        ) {
            var didChange = false
            if existingAtPath.folderKey != folderKey {
                existingAtPath.folderKey = folderKey
                didChange = true
            }
            if existingAtPath.parentFolderID != parentID {
                existingAtPath.parentFolderID = parentID
                didChange = true
            }
            if existingAtPath.name != name {
                existingAtPath.name = name
                didChange = true
            }
            if didChange {
                existingAtPath.updatedAt = .now
                try context.save()
            }
            return existingAtPath
        }

        let folder = Folder(
            businessID: businessID,
            folderKey: folderKey,
            name: name,
            relativePath: normalizedRelativePath,
            parentFolderID: parentID
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    @MainActor
    static func ensureClientFolder(client: Client, context: ModelContext) throws -> Folder {
        try FolderService.bootstrapRootIfNeeded(businessID: client.businessID, context: context)

        guard let root = try FolderService.fetchRootFolder(
            businessID: client.businessID,
            context: context
        ) else {
            throw NSError(domain: "Workspace", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Files root folder was not found."
            ])
        }

        let folderKey = keyForClient(client.id)
        let relativePath = pathAppending(root.relativePath, "clients/\(client.id.uuidString)")

        return try upsertFolder(
            businessID: client.businessID,
            folderKey: folderKey,
            relativePath: relativePath,
            name: clientFolderDisplayName(for: client),
            parentID: root.id,
            context: context
        )
    }

    @MainActor
    private static func ensureClientSubfolder(
        client: Client,
        kind: FolderDestinationKind,
        context: ModelContext
    ) throws -> Folder {
        let clientFolder = try ensureClientFolder(client: client, context: context)
        return try upsertFolder(
            businessID: client.businessID,
            folderKey: keyForClientSubfolder(client.id, kind: kind),
            relativePath: pathAppending(clientFolder.relativePath, kind.rawValue),
            name: kind.displayName,
            parentID: clientFolder.id,
            context: context
        )
    }

    @MainActor
    private static func ensureUnsortedFolder(
        business: Business,
        context: ModelContext
    ) throws -> Folder {
        try FolderService.bootstrapRootIfNeeded(businessID: business.id, context: context)
        guard let root = try FolderService.fetchRootFolder(
            businessID: business.id,
            context: context
        ) else {
            throw NSError(domain: "Workspace", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Files root folder was not found."
            ])
        }

        return try upsertFolder(
            businessID: business.id,
            folderKey: keyForUnsorted(business.id),
            relativePath: pathAppending(root.relativePath, "unsorted"),
            name: "Unsorted",
            parentID: root.id,
            context: context
        )
    }

    @MainActor
    static func resolveFolder(
        business: Business,
        client: Client?,
        job: Job?,
        kind: FolderDestinationKind,
        context: ModelContext
    ) throws -> Folder {
        if let job {
            return try fetchJobSubfolder(job: job, kind: kind.jobSubfolderKind, context: context)
        }

        if let client {
            return try ensureClientSubfolder(client: client, kind: kind, context: context)
        }

        let unsorted = try ensureUnsortedFolder(business: business, context: context)
        return try upsertFolder(
            businessID: business.id,
            folderKey: keyForUnsortedSubfolder(business.id, kind: kind),
            relativePath: pathAppending(unsorted.relativePath, kind.rawValue),
            name: kind.displayName,
            parentID: unsorted.id,
            context: context
        )
    }

    @MainActor
    static func ensureJobWorkspace(job: Job, context: ModelContext) throws -> Folder {
        try FolderService.bootstrapRootIfNeeded(businessID: job.businessID, context: context)

        guard let root = try FolderService.fetchRootFolder(
            businessID: job.businessID,
            context: context
        ) else {
            throw NSError(domain: "Workspace", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Files root folder was not found."
            ])
        }

        let parentFolder: Folder
        if let client = try fetchClient(for: job, context: context) {
            parentFolder = try ensureClientFolder(client: client, context: context)
        } else {
            parentFolder = root
        }

        let jobFolder = try upsertFolder(
            businessID: job.businessID,
            folderKey: keyForJob(job.id),
            relativePath: pathAppending(parentFolder.relativePath, "jobs/\(job.id.uuidString)"),
            name: jobFolderDisplayName(for: job),
            parentID: parentFolder.id,
            context: context
        )

        _ = try ensureJobSubfolders(jobFolder: jobFolder, jobId: job.id, context: context)

        job.workspaceFolderKey = jobFolder.id.uuidString
        try context.save()

        return jobFolder
    }

    @MainActor
    static func ensureJobSubfolders(
        jobFolder: Folder,
        jobId: UUID,
        context: ModelContext
    ) throws -> [JobWorkspaceSubfolder: Folder] {
        var resolved: [JobWorkspaceSubfolder: Folder] = [:]

        for kind in JobWorkspaceSubfolder.allCases {
            let folder = try upsertFolder(
                businessID: jobFolder.businessID,
                folderKey: keyForJobSubfolder(jobId, kind: kind),
                relativePath: pathAppending(jobFolder.relativePath, kind.rawValue),
                name: kind.displayName,
                parentID: jobFolder.id,
                context: context
            )
            resolved[kind] = folder
        }

        return resolved
    }

    @MainActor
    static func fetchJobSubfolder(
        job: Job,
        kind: JobWorkspaceSubfolder,
        context: ModelContext
    ) throws -> Folder {
        let workspace = try ensureJobWorkspace(job: job, context: context)

        if let keyed = try FolderService.fetchFolder(
            businessID: workspace.businessID,
            folderKey: keyForJobSubfolder(job.id, kind: kind),
            context: context
        ) {
            if keyed.parentFolderID != workspace.id {
                keyed.parentFolderID = workspace.id
                keyed.updatedAt = .now
                try context.save()
            }
            return keyed
        }

        let all = try ensureJobSubfolders(jobFolder: workspace, jobId: job.id, context: context)
        guard let folder = all[kind] else {
            throw NSError(domain: "Workspace", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to provision job subfolder \(kind.rawValue)."
            ])
        }
        return folder
    }

    @MainActor
    static func syncJobWorkspaceName(job: Job, context: ModelContext) throws {
        guard let key = job.workspaceFolderKey,
              let folderID = UUID(uuidString: key),
              let folder = try context.fetch(
                FetchDescriptor<Folder>(predicate: #Predicate { $0.id == folderID })
              ).first else {
            return
        }

        let desiredName = jobFolderDisplayName(for: job)
        guard folder.name != desiredName else { return }

        folder.name = desiredName
        folder.updatedAt = .now
        try context.save()
    }
}
