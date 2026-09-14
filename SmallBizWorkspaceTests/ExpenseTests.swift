import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers the two computed bridges Expense adds over its raw storage
/// (`category` over `categoryRaw`, `amountDollars` over `amountCents`) and
/// that it participates correctly in business scoping and persistence —
/// mirrors the patterns already used for `Client`/`Job` model coverage.
///
/// Container is held in a property for the test's lifetime — see
/// `QuickStartQueryTests` for why a container built and discarded in the same
/// expression traps on save.
@MainActor
final class ExpenseTests: XCTestCase {

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

    // MARK: - category bridge

    func testCategoryDefaultsToOtherWhenRawIsUnrecognized() {
        let expense = Expense(businessID: UUID())
        expense.categoryRaw = "not-a-real-category"
        XCTAssertEqual(expense.category, .other)
    }

    func testSettingCategoryUpdatesTheRawValue() {
        let expense = Expense(businessID: UUID())
        expense.category = .fuel
        XCTAssertEqual(expense.categoryRaw, ExpenseCategory.fuel.rawValue)
        XCTAssertEqual(expense.category, .fuel)
    }

    func testInitPersistsTheGivenCategory() {
        let expense = Expense(businessID: UUID(), category: .materials)
        XCTAssertEqual(expense.category, .materials)
        XCTAssertEqual(expense.categoryRaw, "materials")
    }

    // MARK: - amountDollars bridge

    func testAmountDollarsReadsCentsAsDollars() {
        let expense = Expense(businessID: UUID(), amountCents: 4250)
        XCTAssertEqual(expense.amountDollars, 42.50, accuracy: 0.0001)
    }

    func testSettingAmountDollarsUpdatesCents() {
        let expense = Expense(businessID: UUID())
        expense.amountDollars = 19.99
        XCTAssertEqual(expense.amountCents, 1999)
    }

    func testAmountDollarsRoundsToTheNearestCent() {
        let expense = Expense(businessID: UUID())
        // Floating point on 19.999 * 100 lands at 1999.899999...; this must
        // round to 2000 cents, not truncate to 1999.
        expense.amountDollars = 19.999
        XCTAssertEqual(expense.amountCents, 2000)
    }

    // MARK: - Business scoping

    func testScopedToFiltersByBusinessID() throws {
        let mine = UUID()
        let theirs = UUID()

        let mineExpense = Expense(businessID: mine, amountCents: 100)
        let theirsExpense = Expense(businessID: theirs, amountCents: 200)
        context.insert(mineExpense)
        context.insert(theirsExpense)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Expense>())
        let scoped = all.scoped(to: mine)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.businessID, mine)
    }

    func testScopedToNilBusinessIDReturnsNothing() throws {
        let expense = Expense(businessID: UUID(), amountCents: 100)
        context.insert(expense)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertTrue(all.scoped(to: nil).isEmpty)
    }

    // MARK: - Persistence

    func testExpensePersistsAllFieldsAcrossSaveAndFetch() throws {
        let businessID = UUID()
        let clientID = UUID()
        let jobID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let expense = Expense(
            businessID: businessID,
            amountCents: 5599,
            category: .equipment,
            vendor: "Home Depot",
            date: date,
            notes: "New ladder",
            isTaxDeductible: false,
            clientID: clientID,
            jobID: jobID
        )
        context.insert(expense)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>()).first
        XCTAssertEqual(fetched?.businessID, businessID)
        XCTAssertEqual(fetched?.amountCents, 5599)
        XCTAssertEqual(fetched?.category, .equipment)
        XCTAssertEqual(fetched?.vendor, "Home Depot")
        XCTAssertEqual(fetched?.date, date)
        XCTAssertEqual(fetched?.notes, "New ladder")
        XCTAssertEqual(fetched?.isTaxDeductible, false)
        XCTAssertEqual(fetched?.clientID, clientID)
        XCTAssertEqual(fetched?.jobID, jobID)
    }

    func testDeletingAnExpenseCascadesItsAttachmentLink() throws {
        let expense = Expense(businessID: UUID(), amountCents: 100)
        context.insert(expense)

        let folder = Folder(businessID: expense.businessID, folderKey: "root", name: "Root", relativePath: "root")
        context.insert(folder)

        let file = FileItem(
            displayName: "receipt",
            originalFileName: "receipt.jpg",
            relativePath: "root/receipt.jpg",
            fileExtension: "jpg",
            uti: "public.jpeg",
            byteCount: 10,
            folderKey: folder.id.uuidString,
            folder: folder
        )
        context.insert(file)

        let attachment = ExpenseAttachment(expense: expense, file: file)
        context.insert(attachment)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseAttachment>()).count, 1)

        context.delete(expense)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseAttachment>()).isEmpty)
        // The file itself is not cascaded — it lives on in the folder workspace.
        XCTAssertEqual(try context.fetch(FetchDescriptor<FileItem>()).count, 1)
    }
}
