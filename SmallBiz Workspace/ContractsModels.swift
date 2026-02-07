//
//  ContractsModels.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/12/26.
//

import Foundation
import SwiftData

enum ContractStatus: String, Codable, CaseIterable {
    case draft
    case sent
    case signed
    case cancelled
}

@Model
final class Contract {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()

    var title: String = ""
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    /// Snapshot of the template name used at time of creation
    var templateName: String = ""
    var templateCategory: String = ""

    /// Final generated contract text snapshot
    var renderedBody: String = ""

    var pdfRelativePath: String = ""

    /// Store status as String for SwiftData
    var statusRaw: String = ContractStatus.draft.rawValue
    var isSigned: Bool {
        statusRaw == ContractStatus.signed.rawValue
    }

    
    // Signing metadata (fast UI / reporting)
    var signedAt: Date? = nil
    var signedByName: String = ""


    /// Relationships (must be optional for CloudKit)
    // Relationships (optional for CloudKit)
    var client: Client? = nil
    var invoice: Invoice? = nil
    @Relationship(inverse: \ContractAttachment.contract) var attachments: [ContractAttachment]? = nil
    
    @Relationship(inverse: \ContractSignature.contract) var signatures: [ContractSignature]? = nil

    
    var job: Job? = nil
    
    // ✅ Optional “generated from” reference (should point to an estimate Invoice)
    var estimate: Invoice? = nil
    
    var resolvedClient: Client? {
        if let c = client { return c }
        if let c = invoice?.client { return c }
        if let c = estimate?.client { return c }
        return nil
    }
    
    
       
    init(
        businessID: UUID = UUID(),
        title: String = "",
        createdAt: Date = Foundation.Date(),
        updatedAt: Date = Foundation.Date(),
        templateName: String = "",
        templateCategory: String = "",
        renderedBody: String = "",
        pdfRelativePath: String = "",
        statusRaw: String = ContractStatus.draft.rawValue,
        client: Client? = nil,
        invoice: Invoice? = nil
    ) {
        self.businessID = businessID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateName = templateName
        self.templateCategory = templateCategory
        self.renderedBody = renderedBody
        self.pdfRelativePath = pdfRelativePath
        self.statusRaw = statusRaw
        self.client = client
        self.invoice = invoice
    }

    var status: ContractStatus {
        get { ContractStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}
