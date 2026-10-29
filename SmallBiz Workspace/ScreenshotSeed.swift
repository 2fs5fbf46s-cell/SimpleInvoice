//
//  ScreenshotSeed.swift
//  SmallBiz Workspace
//

#if DEBUG
import Foundation
import SwiftData

/// Fills an empty simulator with a made-up lawn care business for App Store
/// screenshots. Launch with `-SBWScreenshotSeed`. That flag also points the
/// app at a dead server address (PortalConfig), so none of this reaches the
/// live portal, the launch-email list or anyone's inbox.
@MainActor
enum ScreenshotSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SBWScreenshotSeed")
    }

    /// `-SBWScreen money` opens a tab (clients, money, work); `invoice:1042`
    /// opens that invoice; `collect:1042` also opens its Collect Payment sheet.
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard isRequested, let i = args.firstIndex(of: "-SBWScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// The link that opens a seeded invoice, from its number's digits.
    static func invoiceURL(_ number: String) -> URL? {
        let digits = number.filter(\.isNumber)
        let padded = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        return URL(string: "smallbizworkspace://app/portal/invoice/00000000-0000-0000-0000-\(padded)")
    }

    static func seedIfEmpty(context: ModelContext, activeBusiness: ActiveBusinessStore) {
        // Launch may already have made an empty default business; fill that in.
        guard isRequested,
              (try? context.fetchCount(FetchDescriptor<Invoice>())) == 0
        else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        let business = (try? context.fetch(FetchDescriptor<Business>()).first) ?? {
            let created = Business(name: "", isActive: true)
            context.insert(created)
            return created
        }()
        business.name = "Brightside Lawn & Garden"
        business.stripeAccountId = "acct_screenshot"
        business.stripeOnboardingStatus = "active"
        business.stripeChargesEnabled = true
        business.stripePayoutsEnabled = true
        business.tipsEnabled = true
        let id = business.id

        let profile = (try? context.fetch(FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == id })).first) ?? {
            let created = BusinessProfile(businessID: id)
            context.insert(created)
            return created
        }()
        profile.name = "Brightside Lawn & Garden"
        profile.email = "office@example.com"
        profile.phone = "(555) 014-2290"
        profile.address = "418 Juniper Street\nWilmington, NC 28401"
        profile.brandColorHex = "#1F6B4F"

        func client(_ name: String, _ phone: String, _ address: String) -> Client {
            let c = Client(businessID: id, name: name, email: "", phone: phone, address: address)
            c.createdAt = day(-40)
            context.insert(c)
            return c
        }
        let maria = client("Maria Alvarez", "(555) 013-4471", "22 Bayview Court")
        let james = client("James Whitfield", "(555) 016-2208", "905 Oleander Drive")
        let priya = client("Priya Raman", "(555) 012-7735", "61 Magnolia Lane")
        let becker = client("Tom & Ellen Becker", "(555) 019-3352", "1407 Pine Ridge Road")
        let oakridge = client("Oakridge HOA", "(555) 011-8840", "Oakridge Clubhouse, 300 Oakridge Blvd")
        let brooks = client("Danielle Brooks", "(555) 018-6623", "77 Harbor Walk")

        func job(_ title: String, _ c: Client, _ start: Date, hours: Double, stage: JobStage = .booked) {
            let j = Job(
                businessID: id,
                clientID: c.id,
                title: title,
                startDate: start,
                endDate: start.addingTimeInterval(hours * 3600),
                locationName: c.address,
                stageRaw: stage.rawValue
            )
            context.insert(j)
        }
        job("Weekly mow and edge", maria, day(0, 8), hours: 1, stage: .completed)
        job("Spring cleanup", james, day(0, 10, 30), hours: 2.5, stage: .inProgress)
        job("Hedge trimming", priya, day(0, 13, 30), hours: 1.5)
        job("Irrigation check", becker, day(0, 15, 30), hours: 1)
        job("Common area mowing", oakridge, day(1, 8), hours: 4)
        job("Mulch and planting", brooks, day(2, 9), hours: 5)
        job("Weekly mow and edge", maria, day(7, 8), hours: 1)

        func invoice(
            _ number: String, _ c: Client, _ items: [(String, Double, Double)],
            issued: Int, due: Int, sent: Bool, estimate: Bool = false
        ) -> Invoice {
            // Fixed ids, so screenshots can link straight to a record:
            // smallbizworkspace://app/portal/invoice/<id>
            let digits = number.filter(\.isNumber)
            let lines = items.map { LineItem(itemDescription: $0.0, quantity: $0.1, unitPrice: $0.2) }
            let inv = Invoice(
                businessID: id,
                invoiceNumber: number,
                issueDate: day(issued),
                dueDate: day(due),
                paymentTerms: estimate ? "Valid for 14 days" : "Net 14",
                documentType: estimate ? "estimate" : "invoice",
                portalNeedsUpload: false,
                client: c,
                items: lines
            )
            inv.clientID = c.id
            inv.id = UUID(uuidString: "00000000-0000-0000-0000-\(String(repeating: "0", count: 12 - digits.count))\(digits)") ?? inv.id
            if sent { inv.sentAt = day(issued, 17) }
            context.insert(inv)
            lines.forEach { context.insert($0) }
            return inv
        }

        let overdue = invoice("INV-1041", oakridge, [("Common area mowing (4 visits)", 4, 320), ("Shrub pruning, front entrance", 1, 570)], issued: -20, due: -6, sent: true)
        overdue.lastReminderAt = day(-3)
        let waiting = invoice("INV-1042", james, [("Spring cleanup", 1, 480), ("Debris haul-away", 1, 160)], issued: -2, due: 12, sent: true)
        waiting.viewedAt = day(-1, 19)
        _ = invoice("INV-1043", priya, [("Hedge trimming", 1, 285), ("Fertilizer application", 1, 135)], issued: 0, due: 14, sent: true)
        _ = invoice("INV-1044", maria, [("Weekly mow and edge", 4, 45)], issued: 0, due: 14, sent: false)
        let paidTap = invoice("INV-1039", becker, [("Irrigation repair", 1, 215), ("Sprinkler heads", 4, 17.5)], issued: -4, due: 10, sent: true)
        let paidOnline = invoice("INV-1040", maria, [("Weekly mow and edge", 4, 45)], issued: -9, due: 5, sent: true)

        let quote = invoice("EST-2007", brooks, [("Paver patio, 12 × 14 ft", 1, 2650), ("Perennial bed planting", 1, 550)], issued: -1, due: 13, sent: true, estimate: true)
        quote.estimateStatus = "sent"
        quote.viewedAt = day(0, 7, 40)
        let accepted = invoice("EST-2006", becker, [("Drip irrigation, back beds", 1, 1180)], issued: -6, due: 8, sent: true, estimate: true)
        accepted.estimateStatus = "accepted"
        accepted.estimateAcceptedAt = day(-3, 11)

        try? context.save()
        _ = try? InvoicePaymentService.record(on: paidTap, amountCents: paidTap.balanceDueCents, paidAt: day(-1, 15, 50), method: "card", note: "Tap to Pay on iPhone", source: "tap_to_pay", tipCents: 0, context: context)
        _ = try? InvoicePaymentService.record(on: paidOnline, amountCents: paidOnline.balanceDueCents, paidAt: day(-3, 20, 12), method: "card", note: "Paid online", source: "stripe", context: context)
        try? context.save()

        OnboardingState.markComplete()
        WalkthroughState.markComplete()
        TapToPayAnnouncementView.markShown(for: id)
        activeBusiness.setActiveBusiness(id)
    }
}
#endif
