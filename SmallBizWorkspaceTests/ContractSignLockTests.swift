import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// A signature has to name a specific document.
///
/// Signing was already careful — consent, name, timestamp, IP, stamped PDF — but
/// nothing stopped the text from changing afterwards. The body was a plain
/// `TextEditor` with no guard, and the status picker offered "Draft" on a signed
/// contract, so a signature could be walked back with one tap.
///
/// The backend enforces the same rules in `src/lib/contractSignLock.ts`. The hash
/// must match across both, which is what `testTheHashMatchesTheBackendVector`
/// pins down.
@MainActor
final class ContractSignLockTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private let body = "You agree to pay $500 on delivery."
    private let tampered = "You agree to pay $5000 on delivery."

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeContract(body: String? = nil) throws -> Contract {
        let contract = Contract(
            businessID: UUID(),
            title: "Service Agreement",
            renderedBody: body ?? self.body
        )
        context.insert(contract)
        try context.save()
        return contract
    }

    // MARK: - Hashing

    func testTheHashIgnoresLineEndingsAndSurroundingWhitespace() {
        XCTAssertEqual(ContractSignLock.bodyHash("a\r\nb"), ContractSignLock.bodyHash("a\nb"))
        XCTAssertEqual(ContractSignLock.bodyHash("  text  "), ContractSignLock.bodyHash("text"))
    }

    func testTheHashChangesWhenTheTextChanges() {
        XCTAssertNotEqual(ContractSignLock.bodyHash(body), ContractSignLock.bodyHash(tampered))
    }

    /// The app and the portal compare hashes with each other, so a change to
    /// either side's normalization silently breaks verification everywhere. This
    /// is the known-good value for the empty string, SHA-256 hex.
    func testTheHashMatchesTheBackendVector() {
        XCTAssertEqual(
            ContractSignLock.bodyHash(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            ContractSignLock.bodyHash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // MARK: - Editability

    func testOnlyASignedContractIsLocked() {
        XCTAssertTrue(ContractSignLock.canEditBody(status: .draft))
        XCTAssertTrue(ContractSignLock.canEditBody(status: .sent))
        XCTAssertTrue(ContractSignLock.canEditBody(status: .cancelled))
        XCTAssertFalse(ContractSignLock.canEditBody(status: .signed))
    }

    /// The status picker used to list every case, so a signed contract could be
    /// set back to draft.
    func testTheStatusPickerNeverOffersSigned() {
        XCTAssertFalse(ContractStatus.selectableBeforeSigning.contains(.signed))
        XCTAssertEqual(
            Set(ContractStatus.selectableBeforeSigning),
            [.draft, .sent, .cancelled]
        )
    }

    // MARK: - Integrity

    func testAnUnsignedContractHasNothingToVerify() {
        XCTAssertEqual(
            ContractSignLock.verify(status: .draft, signedBodyHash: nil, currentBody: body),
            .notSigned
        )
    }

    func testMatchingTextVerifiesAsIntact() {
        XCTAssertEqual(
            ContractSignLock.verify(
                status: .signed,
                signedBodyHash: ContractSignLock.bodyHash(body),
                currentBody: body
            ),
            .intact
        )
    }

    /// The whole reason the hash is recorded.
    func testEditedTextIsDetected() {
        XCTAssertEqual(
            ContractSignLock.verify(
                status: .signed,
                signedBodyHash: ContractSignLock.bodyHash(body),
                currentBody: tampered
            ),
            .changedSinceSigning
        )
    }

    func testAContractSignedBeforeHashesExistedIsUnverifiable() {
        for recorded in [nil, "", "   "] {
            XCTAssertEqual(
                ContractSignLock.verify(
                    status: .signed,
                    signedBodyHash: recorded,
                    currentBody: body
                ),
                .unverifiable,
                "must not claim a contract is intact when nothing was recorded"
            )
        }
    }

    // MARK: - Signing a contract

    func testSigningRecordsWhatWasSigned() throws {
        let contract = try makeContract()

        contract.markSigned(byName: "  Ada Lovelace  ")
        try context.save()

        XCTAssertTrue(contract.isSigned)
        XCTAssertEqual(contract.signedByName, "Ada Lovelace")
        XCTAssertNotNil(contract.signedAt)
        XCTAssertEqual(contract.signedBodyHash, ContractSignLock.bodyHash(body))
        XCTAssertEqual(contract.signatureIntegrity, .intact)
    }

    func testEditingAfterSigningIsDetectable() throws {
        let contract = try makeContract()
        contract.markSigned(byName: "Ada Lovelace")
        try context.save()

        contract.renderedBody = tampered
        try context.save()

        XCTAssertEqual(contract.signatureIntegrity, .changedSinceSigning)
        XCTAssertTrue(
            contract.signedLockDescription.contains("no longer matches"),
            "the detail line has to say so, not quietly show the new text"
        )
    }

    func testSigningTwiceKeepsTheOriginalTimestamp() throws {
        let contract = try makeContract()
        let first = Date(timeIntervalSince1970: 1_700_000_000)

        contract.markSigned(byName: "Ada Lovelace", at: first)
        contract.markSigned(byName: "Ada Lovelace", at: Date())

        XCTAssertEqual(contract.signedAt, first)
    }

    func testTheLockLineNamesTheSigner() throws {
        let contract = try makeContract()
        contract.markSigned(byName: "Ada Lovelace", at: Date(timeIntervalSince1970: 1_700_000_000))

        let description = contract.signedLockDescription
        XCTAssertTrue(description.contains("Ada Lovelace"))
        XCTAssertTrue(description.contains("can no longer be changed"))
    }

    // MARK: - Every path that rewrites the body

    /// The split sheet editor rewrites both the body and the title. Guarding only
    /// the button that opens it left the rewrite itself reachable — and the title
    /// is one of the two fields the portal now refuses to change once signed.
    func testTheSplitSheetEditorRefusesToRewriteASignedContract() throws {
        let client = Client(businessID: UUID(), name: "Ada Lovelace")
        context.insert(client)

        let contract = try makeContract()
        contract.markSigned(byName: "Ada Lovelace")
        try context.save()

        var draft = MusicSplitSheetDraft()
        draft.songTitle = "Something Else Entirely"

        let updated = draft.update(
            contract: contract,
            business: nil,
            selectedClient: client
        )

        XCTAssertFalse(updated, "the rewrite has to refuse, not just be hard to reach")
        XCTAssertEqual(contract.renderedBody, body, "and it must change nothing")
        XCTAssertEqual(contract.title, "Service Agreement")
    }

    func testTheSplitSheetEditorStillWorksOnAnUnsignedContract() throws {
        let client = Client(businessID: UUID(), name: "Ada Lovelace")
        context.insert(client)

        let contract = try makeContract()
        try context.save()

        var draft = MusicSplitSheetDraft()
        draft.songTitle = "A New Song"

        let updated = draft.update(
            contract: contract,
            business: nil,
            selectedClient: client
        )

        XCTAssertTrue(updated)
        XCTAssertNotEqual(contract.renderedBody, body, "an unsigned contract is still editable")
    }

    // MARK: - The signature is kept, not just the fact of it

    private func makeSession(businessID: UUID) throws -> PortalSession {
        let session = PortalSession(
            clientID: UUID(),
            businessID: businessID,
            portalIdentityID: UUID(),
            tokenHash: "hash",
            expiresAt: Date().addingTimeInterval(3600),
            deviceLabel: "iPhone"
        )
        context.insert(session)
        try context.save()
        return session
    }

    /// `ContractSignature` was never constructed anywhere. Signing through the
    /// portal rendered the client's drawn signature to a PNG, handed it to
    /// `signContractFromPortal` along with the consent version, session and
    /// device — and the function wrote none of it, setting only the status. Both
    /// read sites (the summary list, the PDF signature block) always found
    /// nothing.
    func testSigningThroughThePortalKeepsTheDrawnSignature() throws {
        let contract = try makeContract()
        let session = try makeSession(businessID: contract.businessID)
        let png = Data("not-really-a-png".utf8)

        let portal = PortalService(modelContext: context)
        try portal.signContractFromPortal(
            contractID: contract.id,
            session: session,
            signerName: "Ada Lovelace",
            signatureType: .drawn,
            signatureImageData: png,
            signatureText: nil,
            consentVersion: "portal-consent-v1",
            deviceLabel: session.deviceLabel
        )

        let signatures = contract.signatures ?? []
        XCTAssertEqual(signatures.count, 1, "the signature itself has to be kept")

        let signature = try XCTUnwrap(signatures.first)
        XCTAssertEqual(signature.signatureImageData, png, "the drawn signature was being dropped")
        XCTAssertEqual(signature.signerName, "Ada Lovelace")
        XCTAssertEqual(signature.signerRole, "client")
        XCTAssertEqual(signature.signatureType, "drawn")
        XCTAssertEqual(signature.consentVersion, "portal-consent-v1")
        XCTAssertEqual(signature.sessionID, session.id)
        XCTAssertEqual(signature.clientID, session.clientID)
        XCTAssertEqual(signature.deviceLabel, "iPhone")
    }

    func testATypedSignatureKeepsItsText() throws {
        let contract = try makeContract()
        let session = try makeSession(businessID: contract.businessID)

        let portal = PortalService(modelContext: context)
        try portal.signContractFromPortal(
            contractID: contract.id,
            session: session,
            signerName: "Ada Lovelace",
            signatureType: .typed,
            signatureImageData: nil,
            signatureText: "Ada Lovelace",
            consentVersion: "portal-consent-v1",
            deviceLabel: nil
        )

        let signature = try XCTUnwrap((contract.signatures ?? []).first)
        XCTAssertEqual(signature.signatureType, "typed")
        XCTAssertEqual(signature.signatureText, "Ada Lovelace")
        XCTAssertNil(signature.signatureImageData)
    }

    /// A signature has to stay verifiable on its own terms, not only through the
    /// contract it hangs off.
    func testTheSignatureRecordsWhatWasSigned() throws {
        let contract = try makeContract()
        let session = try makeSession(businessID: contract.businessID)

        let portal = PortalService(modelContext: context)
        try portal.signContractFromPortal(
            contractID: contract.id,
            session: session,
            signerName: "Ada Lovelace",
            signatureType: .typed,
            signatureImageData: nil,
            signatureText: "Ada Lovelace",
            consentVersion: "portal-consent-v1",
            deviceLabel: nil
        )

        let signature = try XCTUnwrap((contract.signatures ?? []).first)
        XCTAssertEqual(signature.contractBodyHash, ContractSignLock.bodyHash(body))

        contract.renderedBody = tampered
        XCTAssertNotEqual(
            signature.contractBodyHash,
            ContractSignLock.bodyHash(contract.renderedBody),
            "an edit after signing must be detectable from the signature alone"
        )
    }

    func testSigningThroughThePortalLocksTheContract() throws {
        let contract = try makeContract()
        let session = try makeSession(businessID: contract.businessID)

        let portal = PortalService(modelContext: context)
        try portal.signContractFromPortal(
            contractID: contract.id,
            session: session,
            signerName: "Ada Lovelace",
            signatureType: .typed,
            signatureImageData: nil,
            signatureText: "Ada Lovelace",
            consentVersion: "portal-consent-v1",
            deviceLabel: nil
        )

        XCTAssertTrue(contract.isSigned)
        XCTAssertEqual(contract.signatureIntegrity, .intact)
        XCTAssertFalse(ContractSignLock.canEditBody(status: contract.status))

        let signature = try XCTUnwrap((contract.signatures ?? []).first)
        XCTAssertEqual(
            contract.signedAt, signature.signedAt,
            "the contract and its signature must agree on when it happened"
        )
    }

    func testAnUnnamedSignerStillReadsSensibly() throws {
        let contract = try makeContract()
        contract.markSigned()

        XCTAssertFalse(contract.signedLockDescription.contains("by  "))
        XCTAssertTrue(contract.signedLockDescription.contains("Signed"))
    }
}
