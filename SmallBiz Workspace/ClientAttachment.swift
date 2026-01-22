//
//  CientAttachment.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class ClientAttachment {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    // Stable keys (CloudKit-friendly)
    var clientKey: String = ""   // client.id.uuidString
    var fileKey: String = ""     // file.id.uuidString

    // Optional relationships (CloudKit requires optional)
    @Relationship var client: Client? = nil
    @Relationship var file: FileItem? = nil

    init() {}

    init(client: Client, file: FileItem) {
        self.client = client
        self.file = file
        self.clientKey = client.id.uuidString
        self.fileKey = file.id.uuidString
        self.createdAt = .now
    }
}
