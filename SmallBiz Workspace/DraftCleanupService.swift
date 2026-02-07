import Foundation
import SwiftData

enum DraftCleanupService {

    static func cleanupClientDraft(_ client: Client, context: ModelContext) {
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        let clientJobs = jobs.filter { $0.clientID == client.id }
        for job in clientJobs {
            cleanupJobDraft(job, context: context, saveAfter: false)
        }

        context.delete(client)
        try? context.save()
    }

    static func cleanupJobDraft(_ job: Job, context: ModelContext, saveAfter: Bool = true) {
        let allFolders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let allFiles = (try? context.fetch(FetchDescriptor<FileItem>())) ?? []

        if let root = try? FolderService.fetchRootFolder(businessID: job.businessID, context: context) {
            let rootPath = root.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let jobRel = rootPath.isEmpty
                ? "jobs/\(job.id.uuidString)"
                : "\(rootPath)/jobs/\(job.id.uuidString)"

            let folders = allFolders.filter {
                $0.businessID == job.businessID && $0.relativePath.hasPrefix(jobRel)
            }

            let folderIDs = Set(folders.map { $0.id.uuidString })
            for item in allFiles where folderIDs.contains(item.folderKey) {
                context.delete(item)
            }

            for folder in folders.sorted(by: { $0.relativePath.count > $1.relativePath.count }) {
                context.delete(folder)
            }
        }

        context.delete(job)
        if saveAfter {
            try? context.save()
        }
    }
}
