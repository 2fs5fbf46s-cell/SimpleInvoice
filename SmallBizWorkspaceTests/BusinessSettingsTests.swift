import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// The Business sheet's setup steps and row states, one name everywhere, the
/// booking page's link endings and settings, and where website photos live.
@MainActor
final class BusinessSettingsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeProfile(name: String = "Dunn Lawns", email: String = "hi@dunn.test") -> BusinessProfile {
        let profile = BusinessProfile(businessID: businessID)
        profile.name = name
        profile.email = email
        context.insert(profile)
        return profile
    }

    private func makeBusiness() -> Business {
        let business = Business(id: businessID, name: "Dunn Lawns")
        context.insert(business)
        return business
    }

    // MARK: - Setup steps

    func testTheNextStepIsTheFirstThingNotDone() {
        let profile = makeProfile(email: "")
        XCTAssertEqual(BusinessSetup(profile: profile, business: makeBusiness()).nextStep, .contact)

        profile.email = "hi@dunn.test"
        XCTAssertEqual(BusinessSetup(profile: profile, business: nil).nextStep, .logo)

        profile.logoData = Data([1])
        XCTAssertEqual(BusinessSetup(profile: profile, business: nil).nextStep, .payments)
    }

    func testEverythingDoneHasNoNextStep() {
        let profile = makeProfile()
        profile.logoData = Data([1])
        profile.overdueReminderEnabled = true
        let business = makeBusiness()
        business.venmoEnabled = true
        business.venmoHandleOrLink = "@dunn"
        let setup = BusinessSetup(profile: profile, business: business)
        XCTAssertNil(setup.nextStep)
        XCTAssertEqual(setup.doneCount, setup.totalCount)
    }

    // MARK: - Payment methods

    func testAMethodCountsOnlyWhenOnAndUsable() {
        let business = makeBusiness()
        business.venmoEnabled = true
        XCTAssertEqual(PaymentMethodSummary(business: business).offered, [], "on with no handle isn't usable")
        business.venmoHandleOrLink = "@dunn"
        XCTAssertEqual(PaymentMethodSummary(business: business).offered, ["Venmo"])
    }

    func testTheCardSwitchReallyTurnsCardPaymentsOff() {
        let business = makeBusiness()
        business.stripeAccountId = "acct_1"
        business.stripeChargesEnabled = true
        business.stripePayoutsEnabled = true
        XCTAssertTrue(business.cardPaymentsOffered)
        business.stripeOffered = false
        XCTAssertFalse(business.cardPaymentsOffered)
        XCTAssertTrue(business.stripeReady, "switching off doesn't disconnect Stripe")
        XCTAssertEqual(PaymentMethodSummary(business: business).offered, [])
    }

    func testTheSummaryShortensLongLists() {
        let business = makeBusiness()
        business.venmoEnabled = true; business.venmoHandleOrLink = "@a"
        business.cashAppEnabled = true; business.cashAppHandleOrLink = "$a"
        business.squareEnabled = true; business.squareLink = "https://sq"
        business.achEnabled = true; business.achInstructions = "Wire to…"
        XCTAssertEqual(PaymentMethodSummary(business: business).text, "Venmo, Cash App and 2 more")
    }

    // MARK: - One name

    func testRenamingKeepsEveryCopyOfTheNameInStep() throws {
        let profile = makeProfile(name: "Dunn Lawns")
        let business = makeBusiness()
        let site = BusinessSitePublishService.shared.draft(for: businessID, context: context)
        site.appName = "Dunn Lawns"
        try context.save()

        BusinessIdentity.rename(profile: profile, business: business, to: "  Dunn Lawn & Garden ", context: context)

        XCTAssertEqual(profile.name, "Dunn Lawn & Garden")
        XCTAssertEqual(business.name, "Dunn Lawn & Garden")
        XCTAssertEqual(profile.bookingBrandName, "Dunn Lawn & Garden")
        XCTAssertEqual(site.appName, "Dunn Lawn & Garden")
    }

    func testAWebsiteNameTheOwnerChoseSeparatelyIsKept() {
        let profile = makeProfile(name: "Dunn Lawns")
        let site = BusinessSitePublishService.shared.draft(for: businessID, context: context)
        site.appName = "Dunn's Garden Studio"
        BusinessIdentity.rename(profile: profile, business: nil, to: "Dunn Lawn Co", context: context)
        XCTAssertEqual(site.appName, "Dunn's Garden Studio")
    }

    func testInitials() {
        XCTAssertEqual(BusinessIdentity.initials(for: "Default Business"), "DB")
        XCTAssertEqual(BusinessIdentity.initials(for: "Acme"), "AC")
        XCTAssertEqual(BusinessIdentity.initials(for: "  "), "?")
    }

    // MARK: - Booking page

    func testLinkEndingsAreSuggestedFromTheName() {
        XCTAssertEqual(BookingLink.suggestedSlug(from: "Dunn's Lawn & Garden"), "dunns-lawn-garden")
        XCTAssertEqual(BookingLink.suggestedSlug(from: "A"), "a-biz")
        XCTAssertEqual(BookingLink.suggestedSlug(from: "!!!"), "book")
        XCTAssertLessThanOrEqual(BookingLink.suggestedSlug(from: String(repeating: "long name ", count: 10)).count, 32)
        XCTAssertTrue(BookingLink.isValid(BookingLink.suggestedSlug(from: "Default Business")))
    }

    func testOnlyValidLinkEndingsAreAccepted() {
        XCTAssertTrue(BookingLink.isValid("dunn-lawns"))
        XCTAssertFalse(BookingLink.isValid("du"))
        XCTAssertFalse(BookingLink.isValid("Dunn"))
        XCTAssertFalse(BookingLink.isValid("-dunn"))
        XCTAssertFalse(BookingLink.isValid("dunn lawns"))
        XCTAssertEqual(BookingLink.normalized(" Dunn Lawns "), "dunn-lawns")
    }

    func testTheBookingPageUsesTheProfilesNameAndEmail() {
        let profile = makeProfile(name: "Dunn Lawns", email: "hi@dunn.test")
        profile.bookingBrandName = "Old Name"
        profile.bookingOwnerEmail = "old@dunn.test"
        profile.bookingSlug = "dunn-lawns"
        profile.bookingEnabled = false
        profile.bookingInstructions = "  Gate code 1234. "
        let dto = BookingPageStore.settingsDTO(for: profile)
        XCTAssertEqual(dto.brandName, "Dunn Lawns")
        XCTAssertEqual(dto.ownerEmail, "hi@dunn.test")
        XCTAssertEqual(dto.acceptingBookings, false, "Taking bookings used to stay on the phone")
        XCTAssertEqual(dto.clientNote, "Gate code 1234.", "the note used to stay on the phone")
        XCTAssertEqual(dto.slug, "dunn-lawns")
    }

    func testServicesAndHoursAreSavedOnThePhoneBeforeSyncing() throws {
        let profile = makeProfile()
        var hours = BookingHoursRow.defaults()
        hours[2].isOpen = true
        BookingPageStore.store(
            services: [BookingServiceOption(name: " Mowing ", durationMinutes: 60), BookingServiceOption(name: "  ", durationMinutes: 30)],
            hours: hours,
            into: profile
        )
        XCTAssertEqual(BookingPageStore.services(profile).map(\.name), ["Mowing"])
        let config = try XCTUnwrap(PortalHoursConfig.fromJSON(profile.bookingHoursJSON))
        XCTAssertEqual(config.days[.wed]?.isOpen, true)
        XCTAssertEqual(config.days[.mon]?.isOpen, false)
    }

    func testUnchangedSettingsHaveTheSameSignature() {
        let profile = makeProfile()
        let before = BookingPageStore.signature(profile)
        XCTAssertEqual(BookingPageStore.signature(profile), before)
        profile.bookingAllowSameDay = true
        XCTAssertNotEqual(BookingPageStore.signature(profile), before)
    }

    // MARK: - Website photos

    func testWebsitePhotosAreFoundAgainAfterTheAppFolderMoves() throws {
        let path = try WebsiteImageStore.write(Data([1, 2, 3]), fileName: "hero-test-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertFalse(path.hasPrefix(FileManager.default.temporaryDirectory.path), "not the temporary folder")
        XCTAssertEqual(WebsiteImageStore.resolve(path), path)

        let moved = "/var/mobile/Containers/Data/Application/OLD-FOLDER/Library/" + URL(fileURLWithPath: path).lastPathComponent
        XCTAssertEqual(WebsiteImageStore.resolve(moved), path)
        XCTAssertNil(WebsiteImageStore.resolve("/nowhere/missing.jpg"))
    }

    // MARK: - Alerts

    func testTheRecapTimeRoundTrips() throws {
        let date = try XCTUnwrap(NotificationSettingsView.date(fromHHmm: "07:30"))
        XCTAssertEqual(NotificationSettingsView.hhmm(date), "07:30")
        XCTAssertNil(NotificationSettingsView.date(fromHHmm: "7"))
    }
}
