//
//  ContractSignature.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftData

@Model
final class ContractSignature {

    // MARK: - Identity
    var id: UUID = UUID()

    // MARK: - Ownership / Scope
    var businessID: UUID = UUID()
    var clientID: UUID = UUID()
    var sessionID: UUID? = nil

    // MARK: - Relationship
    var contract: Contract? = nil

    // MARK: - Signer Info
    var signerRole: String = "client"     // "client" | "business"
    var signerName: String = ""

    // MARK: - Signature Data
    var signatureType: String = "drawn"   // "drawn" | "typed"
    var signatureImageData: Data? = nil
    var signatureText: String? = nil

    // MARK: - Legal Metadata
    var signedAt: Date = Date()
    var consentVersion: String = "portal-consent-v1"
    var contractBodyHash: String? = nil

    // MARK: - Device / Audit
    var deviceLabel: String? = nil

    // MARK: - Init
    init(
        businessID: UUID,
        clientID: UUID,
        contract: Contract,
        sessionID: UUID?,
        signerRole: String,
        signerName: String,
        signatureType: String,
        signatureImageData: Data?,
        signatureText: String?,
        consentVersion: String,
        contractBodyHash: String?,
        deviceLabel: String?
    ) {
        self.businessID = businessID
        self.clientID = clientID
        self.contract = contract
        self.sessionID = sessionID
        self.signerRole = signerRole
        self.signerName = signerName
        self.signatureType = signatureType
        self.signatureImageData = signatureImageData
        self.signatureText = signatureText
        self.consentVersion = consentVersion
        self.contractBodyHash = contractBodyHash
        self.deviceLabel = deviceLabel
        self.signedAt = Date()
    }
}
