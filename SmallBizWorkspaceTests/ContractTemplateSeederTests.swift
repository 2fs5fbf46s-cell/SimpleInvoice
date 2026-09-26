import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `ContractTemplateSeeder`'s upgrade path: a built-in template's
/// canned text changed (job/deposit/full standard-terms content added), and
/// existing installs need the new text without losing anyone's own edit —
/// the template detail screen explicitly invites editing a built-in
/// template's body ("You can change its text").
@MainActor
final class ContractTemplateSeederTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func fetchTemplate(named name: String) throws -> ContractTemplate {
        let all = try context.fetch(FetchDescriptor<ContractTemplate>())
        return try XCTUnwrap(all.first { $0.name == name })
    }

    func testFreshInstallSeedsCurrentTemplatesAtCurrentVersion() throws {
        ContractTemplateSeeder.seedIfNeeded(context: context)

        let general = try fetchTemplate(named: "General Service Agreement")
        XCTAssertTrue(general.body.contains("PAYMENT SCHEDULE"))
        XCTAssertTrue(general.body.contains("{{Job.Location}}"), "the template source keeps its {{}} tokens until rendered")
        XCTAssertGreaterThan(general.version, 1)
    }

    func testAnUntouchedV1TemplateIsUpgradedToTheNewText() throws {
        // Simulate an existing install seeded before this change: the old
        // canned body, at version 1, never touched by the owner.
        let legacyBody = """
        SERVICE AGREEMENT

        This Service Agreement (“Agreement”) is made on {{Today}} between:

        Provider: {{Business.Name}}
        Email: {{Business.Email}} | Phone: {{Business.Phone}}
        Address: {{Business.Address}}

        Client: {{Client.Name}}
        Email: {{Client.Email}} | Phone: {{Client.Phone}}
        Address: {{Client.Address}}

        1. SCOPE OF SERVICES
        The Provider agrees to perform the services described below:
        {{Invoice.Items}}

        2. FEES & PAYMENT
        Total Amount: {{Invoice.Total}}
        Due Date: {{Invoice.DueDate}}

        3. CANCELLATION / RESCHEDULING
        Client must provide reasonable notice to reschedule. Cancellation terms may apply.

        4. LIMITATION OF LIABILITY
        Provider’s liability is limited to the amounts paid under this Agreement where permitted by law.

        5. ENTIRE AGREEMENT
        This document represents the entire agreement between the parties.

        Provider Signature: _______________________   Date: __________
        Client Signature: _________________________   Date: __________
        """
        let old = ContractTemplate(name: "General Service Agreement", category: "General", body: legacyBody, isBuiltIn: true, version: 1)
        context.insert(old)
        try context.save()

        ContractTemplateSeeder.seedIfNeeded(context: context)

        let upgraded = try fetchTemplate(named: "General Service Agreement")
        XCTAssertTrue(upgraded.body.contains("PAYMENT SCHEDULE"), "should now have the fuller content")
        XCTAssertGreaterThan(upgraded.version, 1)
    }

    func testAnOwnerEditedTemplateIsNeverOverwritten() throws {
        let customized = ContractTemplate(
            name: "General Service Agreement",
            category: "General",
            body: "My own rewritten agreement text, nothing like the default.",
            isBuiltIn: true,
            version: 1
        )
        context.insert(customized)
        try context.save()

        ContractTemplateSeeder.seedIfNeeded(context: context)

        let stillCustom = try fetchTemplate(named: "General Service Agreement")
        XCTAssertEqual(stillCustom.body, "My own rewritten agreement text, nothing like the default.")
    }

    func testSeedingTwiceDoesNotDuplicateTemplates() throws {
        ContractTemplateSeeder.seedIfNeeded(context: context)
        ContractTemplateSeeder.seedIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<ContractTemplate>())
        let names = all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "no duplicate template names")
    }
}
