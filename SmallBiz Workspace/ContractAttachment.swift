//
//  ContractAttachment.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/16/26.
//

import Foundation
import SwiftData

@Model
final class ContractAttachment {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    // Stable keys (CloudKit-friendly + easy predicates)
    var contractKey: String = ""   // contract.id.uuidString
    var fileKey: String = ""       // file.id.uuidString

    // Optional relationships (CloudKit requires optional)
    @Relationship var contract: Contract? = nil
    @Relationship var file: FileItem? = nil

    init() {}

    init(contract: Contract, file: FileItem) {
        self.contract = contract
        self.file = file
        self.contractKey = contract.id.uuidString
        self.fileKey = file.id.uuidString
        self.createdAt = .now
    }
}
