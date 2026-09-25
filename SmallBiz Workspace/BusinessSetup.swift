//
//  BusinessSetup.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// How far the business is set up, and the one thing to do next — the
/// Business sheet's "Next step" card, on the same pattern as each record's.
struct BusinessSetup: Equatable {
    enum Step: String, CaseIterable, Equatable {
        case contact, logo, payments, reminders

        var title: String {
            switch self {
            case .contact: return "Add your contact details"
            case .logo: return "Add your logo"
            case .payments: return "Connect a way to get paid"
            case .reminders: return "Turn on overdue reminders"
            }
        }

        var detail: String {
            switch self {
            case .contact: return "Your name, email and phone go on every invoice, contract and booking email."
            case .logo: return "It goes at the top of invoices, estimates and contracts."
            case .payments: return "Clients can pay invoices by card, PayPal, Venmo and more once one is on."
            case .reminders: return "Clients with an overdue invoice get a polite email, so you don't have to chase."
            }
        }

        var action: String {
            switch self {
            case .contact: return "Add Details"
            case .logo: return "Add Logo"
            case .payments: return "Set Up Payments"
            case .reminders: return "Turn On"
            }
        }
    }

    let done: Set<Step>

    var nextStep: Step? { Step.allCases.first { !done.contains($0) } }
    var doneCount: Int { done.count }
    var totalCount: Int { Step.allCases.count }

    init(done: Set<Step>) { self.done = done }

    init(profile: BusinessProfile?, business: Business?) {
        var done = Set<Step>()
        if let profile {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, email.contains("@") { done.insert(.contact) }
            if profile.logoData != nil { done.insert(.logo) }
            if profile.overdueReminderEnabled { done.insert(.reminders) }
        }
        if let business, !PaymentMethodSummary(business: business).offered.isEmpty {
            done.insert(.payments)
        }
        self.done = done
    }
}

/// What clients can pay with, in plain words, for the sheet's subtitle and
/// the setup step. A method counts only when it's on *and* usable.
struct PaymentMethodSummary: Equatable {
    let offered: [String]

    init(business: Business) {
        func has(_ value: String?) -> Bool {
            !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var names: [String] = []
        if business.cardPaymentsOffered { names.append("Card") }
        if business.paypalEnabled { names.append("PayPal") }
        if business.venmoEnabled, has(business.venmoHandleOrLink) { names.append("Venmo") }
        if business.cashAppEnabled, has(business.cashAppHandleOrLink) { names.append("Cash App") }
        if business.squareEnabled, has(business.squareLink) { names.append("Square") }
        if business.achEnabled, has(business.achInstructions) { names.append("Bank transfer") }
        offered = names
    }

    var text: String {
        switch offered.count {
        case 0: return "None on yet"
        case 1...3: return offered.joined(separator: ", ")
        default: return offered.prefix(2).joined(separator: ", ") + " and \(offered.count - 2) more"
        }
    }
}

extension Business {
    /// Stripe is connected and able to take the money.
    var stripeReady: Bool {
        !(stripeAccountId ?? "").isEmpty && stripeChargesEnabled && stripePayoutsEnabled
    }

    /// "Pay by card" appears on invoices: Stripe is ready and the owner
    /// hasn't switched card payments off.
    var cardPaymentsOffered: Bool { stripeReady && stripeOffered }
}

/// The business's name lives in several places (the switcher's `Business`,
/// the profile that prints on documents, the booking page, the website).
/// Renaming anywhere goes through here so they can't drift apart.
enum BusinessIdentity {
    static func rename(
        profile: BusinessProfile,
        business: Business?,
        to newName: String,
        context: ModelContext
    ) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = trimmed
        business?.name = trimmed
        // The booking page shows the profile's name now; keep the stored copy
        // in step for anything still reading it.
        profile.bookingBrandName = trimmed.isEmpty ? nil : trimmed

        let businessID = profile.businessID
        if let site = try? context.fetch(
            FetchDescriptor<PublishedBusinessSite>(predicate: #Predicate { $0.businessID == businessID })
        ).first {
            let siteName = site.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            if siteName.isEmpty || siteName == old { site.appName = trimmed }
        }
        try? context.save()
    }

    /// Initials for the avatar: "Default Business" → "DB", "Acme" → "AC".
    static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }
}

/// Invoices carry the payment methods they were published with, so when the
/// owner turns one on or off, the invoices clients can still pay are
/// republished and their portal pages show the change.
enum PaymentMethodsPublisher {
    @MainActor
    static func republishOpenInvoices(businessID: UUID, context: ModelContext) async {
        let descriptor = FetchDescriptor<Invoice>(predicate: #Predicate { $0.businessID == businessID })
        let open = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.documentType != "estimate" && $0.wasSent && !$0.isPaid
        }
        guard !open.isEmpty else { return }
        for invoice in open { invoice.portalNeedsUpload = true }
        try? context.save()
        for invoice in open {
            _ = await PortalAutoSyncService.uploadInvoice(invoiceId: invoice.id, context: context)
        }
    }
}
