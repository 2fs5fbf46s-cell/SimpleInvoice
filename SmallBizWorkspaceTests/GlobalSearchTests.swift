import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Search across the whole business (GlobalSearchView, and iPhone Spotlight
/// through SpotlightIndexer). Both read `SearchDocuments` and `SearchEngine`,
/// so these cover what an owner can find by and how it's ordered.
@MainActor
final class GlobalSearchTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let businessID = UUID()

    override func setUp() async throws {
        container = try AppModelContainerFactory.makeInMemoryContainer()
        context = container.mainContext
    }

    private func seed() -> (smith: Client, invoice: Invoice, estimate: Invoice, job: Job, expense: Expense) {
        let smith = Client(businessID: businessID, name: "Jane Smith", email: "jane@example.com", phone: "(555) 123-4567", address: "12 Oak Street")
        let jose = Client(businessID: businessID, name: "José Álvarez")
        context.insert(smith)
        context.insert(jose)

        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: "SI-2026-014",
            client: smith,
            items: [LineItem(itemDescription: "Wedding DJ package", quantity: 1, unitPrice: 2000)]
        )
        let estimate = Invoice(businessID: businessID, invoiceNumber: "EST-7", documentType: "estimate", client: jose)
        context.insert(invoice)
        context.insert(estimate)

        let job = Job(businessID: businessID, clientID: smith.id, title: "Kitchen remodel", startDate: .now, endDate: .now, locationName: "12 Oak Street")
        let otherJob = Job(businessID: businessID, clientID: jose.id, title: "Kitchen tile", startDate: .now, endDate: .now)
        context.insert(job)
        context.insert(otherJob)

        let expense = Expense(businessID: businessID, amountCents: 4_250, category: .fuel, vendor: "Shell")
        context.insert(expense)

        // Another business's client, which must never show up.
        context.insert(Client(businessID: UUID(), name: "Jane Smithson"))
        try? context.save()
        return (smith, invoice, estimate, job, expense)
    }

    private func search(_ query: String) -> [SearchEngine.Section] {
        SearchEngine.sections(for: query, in: SearchDocuments.all(businessID: businessID, context: context))
    }

    private func ids(_ query: String) -> Set<UUID> {
        Set(search(query).flatMap { $0.documents.map(\.recordID) })
    }

    func testEveryWordMustMatch() {
        let seeded = seed()
        // "smith kitchen" is the Smith job, not every Smith and not every kitchen.
        XCTAssertEqual(ids("smith kitchen"), [seeded.job.id])
    }

    func testFindsOnlyThisBusiness() {
        _ = seed()
        let names = search("smith").flatMap { $0.documents.map(\.title) }
        XCTAssertFalse(names.contains("Jane Smithson"))
    }

    func testIgnoresCaseAndAccents() {
        let seeded = seed()
        XCTAssertTrue(ids("JOSE").contains(seeded.estimate.client!.id))
        XCTAssertTrue(ids("alvarez").contains(seeded.estimate.id), "an estimate is found by its client's name")
    }

    func testFindsByPhoneDigitsEmailAndAddress() {
        let seeded = seed()
        XCTAssertTrue(ids("5551234567").contains(seeded.smith.id))
        XCTAssertTrue(ids("jane@example").contains(seeded.smith.id))
        XCTAssertEqual(ids("oak street"), [seeded.smith.id, seeded.job.id])
    }

    func testFindsInvoicesByNumberLineItemAndAmount() {
        let seeded = seed()
        XCTAssertEqual(ids("SI-2026-014"), [seeded.invoice.id])
        XCTAssertEqual(ids("wedding dj"), [seeded.invoice.id])
        XCTAssertEqual(ids("2000"), [seeded.invoice.id])
        XCTAssertEqual(ids("$2,000"), [seeded.invoice.id])
        XCTAssertEqual(ids("42.50"), [seeded.expense.id])
    }

    func testEstimatesAndInvoicesAreSeparateSections() {
        _ = seed()
        let kinds = search("e").map(\.kind)
        XCTAssertEqual(kinds, kinds.sorted { SearchDocument.Kind.allCases.firstIndex(of: $0)! < SearchDocument.Kind.allCases.firstIndex(of: $1)! },
                       "sections come in a fixed order")
        let estimate = search("EST-7").first
        XCTAssertEqual(estimate?.kind, .estimate)
        XCTAssertEqual(estimate?.documents.first?.title, "Estimate EST-7")
    }

    func testTitleMatchesComeFirst() {
        let docs = [
            SearchDocument(kind: .client, recordID: UUID(), title: "Bob", subtitle: "", date: .now, terms: ["works with Smith"]),
            SearchDocument(kind: .client, recordID: UUID(), title: "Smith Plumbing", subtitle: "", date: .distantPast, terms: []),
        ]
        XCTAssertEqual(SearchEngine.sections(for: "smith", in: docs).first?.documents.map(\.title), ["Smith Plumbing", "Bob"],
                       "a title match beats a newer record that only mentions it")
    }

    func testEmptyQueryFindsNothing() {
        _ = seed()
        XCTAssertTrue(search("   ").isEmpty)
    }

    func testLimitReportsTheRealCount() {
        let docs = (0..<30).map { SearchDocument(kind: .job, recordID: UUID(), title: "Fence \($0)", subtitle: "", date: .now, terms: []) }
        let section = SearchEngine.sections(for: "fence", in: docs, limitPerKind: 25).first
        XCTAssertEqual(section?.documents.count, 25)
        XCTAssertEqual(section?.totalCount, 30)
    }

    func testIdentifierRoundTrips() {
        let id = UUID()
        let document = SearchDocument(kind: .contract, recordID: id, title: "T", subtitle: "", date: .now, terms: [])
        let parsed = SearchDocument.parse(document.id)
        XCTAssertEqual(parsed?.kind, .contract)
        XCTAssertEqual(parsed?.recordID, id)
        XCTAssertNil(SearchDocument.parse("invoice:not-a-uuid"))
        XCTAssertNil(SearchDocument.parse("payment:\(UUID().uuidString)"))
    }

    func testRecentRecordsAreNewestFirstWithoutRepeats() {
        let business = UUID()
        for n in 0..<10 { RecentSearchRecords.add("job:\(n)", for: business) }
        RecentSearchRecords.add("job:5", for: business)
        let recent = RecentSearchRecords.ids(for: business)
        XCTAssertEqual(recent.count, RecentSearchRecords.limit)
        XCTAssertEqual(recent.first, "job:5")
        XCTAssertEqual(recent.filter { $0 == "job:5" }.count, 1)
    }
}
