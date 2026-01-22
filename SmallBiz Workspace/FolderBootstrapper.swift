import Foundation
import SwiftData

@MainActor
final class FolderBootstrapper {

    static func ensureDefaultTree(
        modelContext: ModelContext,
        business: Business
    ) {
        let businessID = business.id
        let rootRel = "Business-\(businessID.uuidString)"

        // ✅ Avoid SwiftData #Predicate macro issues by filtering in memory
        let allFolders = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
        if allFolders.contains(where: { $0.businessID == businessID && $0.relativePath == rootRel }) {
            return
        }

        // Create on disk
        try? FileStore.shared.createFolder(relativePath: rootRel)

        // Create root folder
        let root = Folder(
            businessID: businessID,
            name: "Files",
            relativePath: rootRel,
            parentFolderID: nil
        )
        modelContext.insert(root)

        let children = [
            "Clients",
            "Templates",
            "Receipts",
            "Legal",
            "Exports"
        ]

        for name in children {
            let rel = "\(rootRel)/\(name)"
            try? FileStore.shared.createFolder(relativePath: rel)

            let f = Folder(
                businessID: businessID,
                name: name,
                relativePath: rel,
                parentFolderID: root.id
            )
            modelContext.insert(f)
        }

        AuditLogger.shared.log(
            modelContext: modelContext,
            businessID: businessID,
            entityType: "Business",
            entityID: businessID,
            action: .create,
            summary: "Initialized default folder tree"
        )

        try? modelContext.save()
    }
}
