import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `Client.leadSource`, the JSON-free String↔enum bridge over
/// `leadSourceRaw` — same idiom as `Expense.category`/`categoryRaw`, except
/// optional: most existing clients predate this field, and it should read
/// as "not set," never a guessed default.
@MainActor
final class ClientLeadSourceTests: XCTestCase {

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

    func testNewClientHasNoLeadSourceByDefault() {
        let client = Client(businessID: UUID(), name: "Ana Lopez")
        XCTAssertNil(client.leadSource)
        XCTAssertNil(client.leadSourceRaw)
    }

    func testSettingAndClearingLeadSourceRoundTripsThroughRawStorage() {
        let client = Client(businessID: UUID(), name: "Ana Lopez")

        client.leadSource = .referral
        XCTAssertEqual(client.leadSourceRaw, "referral")
        XCTAssertEqual(client.leadSource, .referral)

        client.leadSource = nil
        XCTAssertNil(client.leadSourceRaw)
        XCTAssertNil(client.leadSource)
    }

    func testAllCasesRoundTrip() {
        let client = Client(businessID: UUID(), name: "Ana Lopez")
        for source in LeadSource.allCases {
            client.leadSource = source
            XCTAssertEqual(client.leadSource, source)
        }
    }

    func testLeadSourcePersistsAcrossASaveAndRefetch() throws {
        let client = Client(businessID: UUID(), name: "Ana Lopez")
        client.leadSource = .googleSearch
        context.insert(client)
        try context.save()

        let clientID = client.id
        let refetched = try XCTUnwrap((try context.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientID })
        )).first)

        XCTAssertEqual(refetched.leadSource, .googleSearch)
    }

    func testUnrecognizedRawValueDecodesToNilRatherThanCrashing() {
        let client = Client(businessID: UUID(), name: "Ana Lopez")
        client.leadSourceRaw = "some-future-source-this-build-does-not-know"
        XCTAssertNil(client.leadSource)
    }
}
