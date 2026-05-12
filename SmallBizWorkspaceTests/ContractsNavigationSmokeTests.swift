import XCTest
import SwiftData
import SwiftUI
@testable import SmallBizWorkspace

final class ContractsNavigationSmokeTests: XCTestCase {
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

    func testContractsViewsAcceptExplicitBusinessID() {
        let businessID = UUID()

        let home = ContractsHomeView(businessID: businessID)
        let list = ContractsListView(businessID: businessID)
        let templates = ContractTemplatesView(businessID: businessID)
        let picker = ContractTemplatePickerView(businessID: businessID)
        let start = CreateContractStartView(businessID: businessID)

        XCTAssertNotNil(home)
        XCTAssertNotNil(list)
        XCTAssertNotNil(templates)
        XCTAssertNotNil(picker)
        XCTAssertNotNil(start)
    }

    @MainActor
    func testContractCreationUsesExplicitBusinessID() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let businessID = UUID()
        let template = ContractTemplate(name: "Service Agreement", category: "General", body: "Hello {{Client.Name}}")
        context.insert(template)

        let contract = try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: nil,
            invoice: nil
        )

        XCTAssertEqual(contract.businessID, businessID)
    }

    @MainActor
    func testSeederAddsMusicSplitSheetToExistingTemplateStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(ContractTemplate(
            name: "General Service Agreement",
            category: "General",
            body: "Existing body",
            isBuiltIn: true,
            version: 1
        ))
        try context.save()

        ContractTemplateSeeder.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<ContractTemplate>())
        let templateNames = templates.map(\.name)

        XCTAssertTrue(templateNames.contains("Music Split Sheet"))
        XCTAssertEqual(templateNames.filter { $0 == "General Service Agreement" }.count, 1)

        let musicTemplate = try XCTUnwrap(templates.first { $0.name == "Music Split Sheet" })
        XCTAssertEqual(musicTemplate.category, "Music / Entertainment")
        XCTAssertTrue(musicTemplate.body.contains("SONGWRITING / PUBLISHING SPLITS"))
        XCTAssertTrue(musicTemplate.body.contains("Total master recording splits must equal 100%."))
    }

    func testMusicSplitSheetDraftValidationFlagsTotalsNamesAndPercentBounds() {
        var contributor = MusicSplitSheetContributor()
        contributor.stageNameOrCompany = "Producer Co"
        contributor.writerSharePercent = 80
        contributor.publishingSharePercent = 100
        contributor.masterOwnershipPercent = 100
        contributor.producerPointsPercent = -1

        var draft = MusicSplitSheetDraft()
        draft.contributors = [contributor]

        let warnings = draft.validationWarnings.joined(separator: "\n")

        XCTAssertFalse(draft.canGenerateContract)
        XCTAssertTrue(warnings.contains("Writer share total must equal 100%. Current total: 80%."))
        XCTAssertTrue(warnings.contains("Producer Co is missing a legal name."))
        XCTAssertTrue(warnings.contains("producer points cannot be negative."))
    }

    func testMusicSplitSheetDraftGeneratesProfessionalContractBody() {
        var writer = MusicSplitSheetContributor()
        writer.legalName = "Alex Writer"
        writer.role = "Writer"
        writer.proAffiliation = "ASCAP"
        writer.ipiCaeNumber = "123456789"
        writer.writerSharePercent = 50
        writer.publishingSharePercent = 50
        writer.masterOwnershipPercent = 40
        writer.royaltyNotes = "Paid quarterly."

        var producer = MusicSplitSheetContributor()
        producer.legalName = "Priya Producer"
        producer.role = "Producer"
        producer.writerSharePercent = 50
        producer.publishingSharePercent = 50
        producer.masterOwnershipPercent = 60
        producer.producerPointsPercent = 3
        producer.isWorkForHire = true
        producer.flatFeeAmount = "$500"
        producer.flatFeePaidDate = "May 1, 2026"
        producer.royaltyNotes = "Producer points survive the flat fee."

        var draft = MusicSplitSheetDraft()
        draft.songTitle = "Midnight Demo"
        draft.artistName = "The Example Artist"
        draft.distributor = "DistroKid"
        draft.releaseDate = "June 1, 2026"
        draft.usesSamples = true
        draft.sampleSource = "Vintage drum break"
        draft.clearanceResponsibility = "Alex Writer"
        draft.clearanceStatus = "Pending"
        draft.proRegistrationResponsibleParty = "Alex Writer"
        draft.distributorUploadResponsibleParty = "Priya Producer"
        draft.paymentReportingSchedule = "Quarterly"
        draft.contributors = [writer, producer]

        XCTAssertTrue(draft.canGenerateContract)

        let body = draft.contractBody(generatedAt: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(body.contains("MUSIC SPLIT SHEET"))
        XCTAssertTrue(body.contains("Song Title: Midnight Demo"))
        XCTAssertTrue(body.contains("Alex Writer | Writer | 50% | 50%"))
        XCTAssertTrue(body.contains("Priya Producer | 60% | 3% | Producer points survive the flat fee."))
        XCTAssertTrue(body.contains("Samples / Interpolations Used: Yes"))
        XCTAssertTrue(body.contains("PRO / Publishing Admin Registration Responsibility: Alex Writer"))
        XCTAssertTrue(body.contains("Contributor Name: Priya Producer"))
    }
}
