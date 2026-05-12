import XCTest
import SwiftData
@testable import SmallBizWorkspace

final class MusicSplitSheetSmartEditingTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Business.self,
            BusinessProfile.self,
            Client.self,
            Invoice.self,
            LineItem.self,
            CatalogItem.self,
            Contract.self,
            ClientAttachment.self,
            JobAttachment.self,
            AuditEvent.self,
            PortalIdentity.self,
            PortalSession.self,
            PortalInvite.self,
            PortalAuditEvent.self,
            EstimateDecisionRecord.self,
            ContractTemplate.self,
            Folder.self,
            FileItem.self,
            InvoiceAttachment.self,
            ContractAttachment.self,
            Job.self,
            Blockout.self
        ])

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testGeneratedSmartSplitSheetStoresTemplateMetadataAndDecodableDraft() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Primary Artist")

        var contributor = MusicSplitSheetContributor()
        contributor.legalName = "Alex Writer"
        contributor.writerSharePercent = 100
        contributor.publishingSharePercent = 100
        contributor.masterOwnershipPercent = 100

        var draft = MusicSplitSheetDraft()
        draft.songTitle = "Metadata Song"
        draft.contributors = [contributor]

        let contract = draft.makeContract(
            businessID: businessID,
            business: nil,
            selectedClient: client,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(contract.smartTemplateType, MusicSplitSheetDraft.smartTemplateType)

        let json = try XCTUnwrap(contract.smartTemplateJSON)
        let decodedDraft = try XCTUnwrap(MusicSplitSheetDraft.decodeJSONString(json))
        XCTAssertEqual(decodedDraft, draft)
    }

    func testEditingSmartSplitSheetDraftRegeneratesBodyOnSameContract() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Primary Artist")
        let job = Job(
            businessID: businessID,
            clientID: client.id,
            title: "Release Prep",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3_600)
        )

        var contributor = MusicSplitSheetContributor()
        contributor.legalName = "Alex Writer"
        contributor.writerSharePercent = 100
        contributor.publishingSharePercent = 100
        contributor.masterOwnershipPercent = 100

        var draft = MusicSplitSheetDraft()
        draft.songTitle = "Original Song"
        draft.contributors = [contributor]

        let contract = draft.makeContract(
            businessID: businessID,
            business: nil,
            selectedClient: client,
            linkedJob: job,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let originalID = contract.id
        contract.portalNeedsUpload = false

        var editedDraft = try XCTUnwrap(MusicSplitSheetDraft.decodeJSONString(contract.smartTemplateJSON))
        editedDraft.songTitle = "Edited Song"
        editedDraft.contributors[0].royaltyNotes = "Updated after review."

        editedDraft.update(
            contract: contract,
            business: nil,
            selectedClient: client,
            updatedAt: Date(timeIntervalSince1970: 86_400)
        )

        XCTAssertEqual(contract.id, originalID)
        XCTAssertEqual(contract.title, "Music Split Sheet - Edited Song")
        XCTAssertEqual(contract.client?.id, client.id)
        XCTAssertEqual(contract.job?.id, job.id)
        XCTAssertEqual(contract.linkedJobIDsCSV, job.id.uuidString)
        XCTAssertTrue(contract.portalNeedsUpload)
        XCTAssertTrue(contract.renderedBody.contains("Song Title: Edited Song"))
        XCTAssertFalse(contract.renderedBody.contains("Song Title: Original Song"))
        XCTAssertTrue(contract.renderedBody.contains("Updated after review."))

        let decodedDraft = try XCTUnwrap(MusicSplitSheetDraft.decodeJSONString(contract.smartTemplateJSON))
        XCTAssertEqual(decodedDraft.songTitle, "Edited Song")
        XCTAssertEqual(decodedDraft.contributors.first?.royaltyNotes, "Updated after review.")
    }

    @MainActor
    func testStaticMusicSplitSheetTemplateStillWorksWithoutSmartMetadata() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Static Template Client")

        context.insert(client)
        ContractTemplateSeeder.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<ContractTemplate>())
        let template = try XCTUnwrap(templates.first { $0.name == "Music Split Sheet" })

        let contract = try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: client,
            invoice: nil
        )

        XCTAssertEqual(contract.templateName, "Music Split Sheet")
        XCTAssertNil(contract.smartTemplateType)
        XCTAssertNil(contract.smartTemplateJSON)
        XCTAssertTrue(contract.renderedBody.contains("MUSIC SPLIT SHEET"))
    }
}
