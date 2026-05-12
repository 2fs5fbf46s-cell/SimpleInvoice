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
}
