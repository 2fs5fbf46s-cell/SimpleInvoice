//
//  JobWorkspaceFactory.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

enum JobWorkspaceFactory {

    /// Creates a Job for a client and provisions the Files workspace (Job root + default subfolders).
    /// Uses WorkspaceProvisioningService to avoid Folder initializer mismatches.
    @MainActor
    static func createInitialJobAndWorkspace(
        context: ModelContext,
        businessID: UUID,
        client: Client,
        jobTitle: String? = nil
    ) throws -> Job {

        let title = (jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultJobTitle(for: client)

        // Your Job init signature is already used elsewhere in your app.
        let job = Job(
            businessID: businessID,
            clientID: client.id,
            title: title,
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )

        job.status = job.status.isEmpty ? "scheduled" : job.status

        context.insert(job)
        try context.save()

        // ✅ Provision Files workspace using the service you already have working
        _ = try WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: context)

        return job
    }

    private static func defaultJobTitle(for client: Client) -> String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "New Job" : "\(name) Job"
    }
}
