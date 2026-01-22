//
//  JobAttachment.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class JobAttachment {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    var jobKey: String = ""      // job.id.uuidString
    var fileKey: String = ""     // file.id.uuidString

    @Relationship var job: Job? = nil
    @Relationship var file: FileItem? = nil

    init() {}

    init(job: Job, file: FileItem) {
        self.job = job
        self.file = file
        self.jobKey = job.id.uuidString
        self.fileKey = file.id.uuidString
        self.createdAt = .now
    }
}
