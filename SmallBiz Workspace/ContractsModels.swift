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
    var smartTemplateType: String? = nil
    var smartTemplateJSON: String? = nil

    var pdfRelativePath: String = ""
    var portalNeedsUpload: Bool = true
    var portalUploadInFlight: Bool = false
    var portalLastUploadedAtMs: Int64? = nil
    var portalLastUploadError: String? = nil
    var portalLastUploadedHash: String? = nil

    /// Store status as String for SwiftData
    var statusRaw: String = ContractStatus.draft.rawValue
    var isSigned: Bool {
        statusRaw == ContractStatus.signed.rawValue
    }

    
    // Signing metadata (fast UI / reporting)
    var signedAt: Date? = nil
    var signedByName: String = ""

    /// SHA-256 of the body at the moment it was signed. See `ContractSignLock`:
    /// without this, a signature says a document was agreed to but nothing says
    /// which document, so a later edit is undetectable.
    var signedBodyHash: String? = nil


    /// Relationships (must be optional for CloudKit)
    // Relationships (optional for CloudKit)
    var client: Client? = nil
    var invoice: Invoice? = nil
    @Relationship(inverse: \ContractAttachment.contract) var attachments: [ContractAttachment]? = nil
    
    @Relationship(inverse: \ContractSignature.contract) var signatures: [ContractSignature]? = nil

    
    var job: Job? = nil
    // Stores all linked job ids (including primary) as comma-separated UUIDs.
    var linkedJobIDsCSV: String = ""
    
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
        smartTemplateType: String? = nil,
        smartTemplateJSON: String? = nil,
        pdfRelativePath: String = "",
        portalNeedsUpload: Bool = true,
        portalUploadInFlight: Bool = false,
        portalLastUploadedAtMs: Int64? = nil,
        portalLastUploadError: String? = nil,
        portalLastUploadedHash: String? = nil,
        statusRaw: String = ContractStatus.draft.rawValue,
        client: Client? = nil,
        invoice: Invoice? = nil,
        linkedJobIDsCSV: String = ""
    ) {
        self.businessID = businessID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateName = templateName
        self.templateCategory = templateCategory
        self.renderedBody = renderedBody
        self.smartTemplateType = smartTemplateType
        self.smartTemplateJSON = smartTemplateJSON
        self.pdfRelativePath = pdfRelativePath
        self.portalNeedsUpload = portalNeedsUpload
        self.portalUploadInFlight = portalUploadInFlight
        self.portalLastUploadedAtMs = portalLastUploadedAtMs
        self.portalLastUploadError = portalLastUploadError
        self.portalLastUploadedHash = portalLastUploadedHash
        self.statusRaw = statusRaw
        self.client = client
        self.invoice = invoice
        self.linkedJobIDsCSV = linkedJobIDsCSV
    }

    var status: ContractStatus {
        get { ContractStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// Mark this contract signed and record what was signed, in one place so the
    /// hash can never be forgotten at one of the call sites.
    func markSigned(byName: String = "", at date: Date = Date()) {
        statusRaw = ContractStatus.signed.rawValue
        signedBodyHash = ContractSignLock.bodyHash(renderedBody)
        if signedAt == nil { signedAt = date }
        let trimmed = byName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { signedByName = trimmed }
    }

    var signatureIntegrity: ContractSignLock.Integrity {
        ContractSignLock.verify(
            status: status,
            signedBodyHash: signedBodyHash,
            currentBody: renderedBody
        )
    }

    /// The line shown under a locked contract body.
    var signedLockDescription: String {
        switch signatureIntegrity {
        case .changedSinceSigning:
            return "This text no longer matches what was signed."
        case .intact, .unverifiable, .notSigned:
            let who = signedByName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let signedAt {
                let when = signedAt.formatted(date: .abbreviated, time: .shortened)
                return who.isEmpty
                    ? "Signed \(when). This text can no longer be changed."
                    : "Signed by \(who) on \(when). This text can no longer be changed."
            }
            return who.isEmpty
                ? "Signed. This text can no longer be changed."
                : "Signed by \(who). This text can no longer be changed."
        }
    }
}
