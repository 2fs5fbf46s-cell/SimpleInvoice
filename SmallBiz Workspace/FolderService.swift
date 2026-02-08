import Foundation
import SwiftData

enum FolderService {

    // MARK: - Bootstrap

    static func bootstrapRootIfNeeded(businessID: UUID, context: ModelContext) throws {
        let root = try fetchRootFolder(businessID: businessID, context: context)
        if root == nil {
            let newRoot = Folder(
                id: UUID(),
                businessID: businessID,
                folderKey: "root:\(businessID.uuidString)",
                name: "Files",
                relativePath: "Files",
                parentFolderID: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            context.insert(newRoot)
            try context.save()
        }
    }

    // MARK: - Fetch (macro-safe)

    static func fetchRootFolder(businessID: UUID, context: ModelContext) throws -> Folder? {
        // ✅ parentFolderID == nil is safe in macro
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.businessID == businessID &&
                folder.parentFolderID == nil &&
                folder.name == "Files"
            }
        )
        return try context.fetch(descriptor).first
    }

    static func fetchAllFolders(businessID: UUID, context: ModelContext) throws -> [Folder] {
        // ✅ only compares non-optional UUID
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.businessID == businessID
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    static func fetchChildren(businessID: UUID, parentID: UUID?, context: ModelContext) throws -> [Folder] {
        // ✅ Avoid Optional equality in predicates. Filter in memory.
        let all = try fetchAllFolders(businessID: businessID, context: context)
        return all
            .filter { $0.parentFolderID == parentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func fetchFolderByID(_ id: UUID, context: ModelContext) throws -> Folder? {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { f in f.id == id }
        )
        return try context.fetch(descriptor).first
    }

    static func fetchFolder(
        businessID: UUID,
        relativePath: String,
        context: ModelContext
    ) throws -> Folder? {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.businessID == businessID &&
                folder.relativePath == relativePath
            }
        )
        return try context.fetch(descriptor).first
    }

    static func fetchFolder(
        businessID: UUID,
        folderKey: String,
        context: ModelContext
    ) throws -> Folder? {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { folder in
                folder.businessID == businessID &&
                folder.folderKey == folderKey
            }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Create / Rename (conflict-safe)

    static func createFolder(
        businessID: UUID,
        name: String,
        parent: Folder,
        context: ModelContext
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let siblingNames = try fetchFolderNamesInParent(
            businessID: businessID,
            parentID: parent.id,
            context: context
        )
        let uniqueName = makeUniqueName(base: trimmed, used: Set(siblingNames))

        let parentPath = parent.relativePath.isEmpty ? parent.name : parent.relativePath
        let relPath = "\(parentPath)/\(uniqueName)"

        let folder = Folder(
            id: UUID(),
            businessID: businessID,
            name: uniqueName,
            relativePath: relPath,
            parentFolderID: parent.id,
            createdAt: Date(),
            updatedAt: Date()
        )

        context.insert(folder)
        parent.updatedAt = Date()
        try context.save()
    }

    static func renameFolder(folder: Folder, newName: String, context: ModelContext) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let siblingNames = try fetchFolderNamesInParent(
            businessID: folder.businessID,
            parentID: folder.parentFolderID,
            context: context
        )

        let uniqueName = makeUniqueName(
            base: trimmed,
            used: Set(siblingNames.filter { $0 != folder.name })
        )

        folder.name = uniqueName
        folder.updatedAt = .now

        // Update relativePath based on parent (in-memory fetch)
        if let parentID = folder.parentFolderID,
           let parent = try fetchFolderByID(parentID, context: context) {
            let parentPath = parent.relativePath.isEmpty ? parent.name : parent.relativePath
            folder.relativePath = "\(parentPath)/\(folder.name)"
        } else {
            folder.relativePath = (folder.name == "Files") ? "Files" : "Files/\(folder.name)"
        }

        try context.save()
        try updateDescendantPaths(folder: folder, context: context)
    }

    // MARK: - Move (conflict-safe + recursive path update)

    static func moveFolder(folder: Folder, newParent: Folder?, context: ModelContext) throws {
        let businessID = folder.businessID

        let root = try fetchRootFolder(businessID: businessID, context: context)
        let effectiveParent: Folder? = (newParent ?? root)

        // Conflict-safe name under destination
        let usedNames = try fetchFolderNamesInParent(
            businessID: businessID,
            parentID: effectiveParent?.id,
            context: context
        )
        folder.name = makeUniqueName(base: folder.name, used: Set(usedNames.filter { $0 != folder.name }))

        folder.parentFolderID = effectiveParent?.id

        let parentPath: String = {
            if let p = effectiveParent {
                return p.relativePath.isEmpty ? p.name : p.relativePath
            }
            return "Files"
        }()

        folder.relativePath = "\(parentPath)/\(folder.name)"
        folder.updatedAt = .now

        try context.save()
        try updateDescendantPaths(folder: folder, context: context)
    }

    static func updateDescendantPaths(folder: Folder, context: ModelContext) throws {
        // ✅ macro-safe: fetch by businessID, filter in memory
        let all = try fetchAllFolders(businessID: folder.businessID, context: context)
        let kids = all.filter { $0.parentFolderID == folder.id }

        for child in kids {
            let parentPath = folder.relativePath.isEmpty ? folder.name : folder.relativePath
            child.relativePath = "\(parentPath)/\(child.name)"
            child.updatedAt = .now
        }

        try context.save()

        // Recurse after save (kids updated)
        for child in kids {
            try updateDescendantPaths(folder: child, context: context)
        }
    }

    // MARK: - File move conflict helper

    static func fetchFileDisplayNamesInFolder(folderID: UUID?, context: ModelContext) throws -> [String] {
        guard let folderID else { return [] }
        let folderKey = folderID.uuidString

        let descriptor = FetchDescriptor<FileItem>(
            predicate: #Predicate<FileItem> { item in
                item.folderKey == folderKey
            }
        )
        return try context.fetch(descriptor).map { $0.displayName }
    }

    // MARK: - Folder name helpers (macro-safe)

    static func fetchFolderNamesInParent(businessID: UUID, parentID: UUID?, context: ModelContext) throws -> [String] {
        let all = try fetchAllFolders(businessID: businessID, context: context)
        return all.filter { $0.parentFolderID == parentID }.map { $0.name }
    }

    // MARK: - Unique name generator

    static func makeUniqueName(base: String, used: Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        if !used.contains(trimmed) { return trimmed }

        var i = 1
        while true {
            let candidate = "\(trimmed) (\(i))"
            if !used.contains(candidate) { return candidate }
            i += 1
        }
    }
}
