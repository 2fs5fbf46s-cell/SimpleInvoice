import Foundation
import SwiftData

@Model
final class Business {
    var id: UUID = UUID()
    var name: String = ""
    var isActive: Bool = true

    var defaultTaxRate: Decimal = 0
    var currencyCode: String = "USD"
    var defaultInvoiceTemplateKey: String = InvoiceTemplateKey.modern_clean.rawValue

    var paypalMeUrl: String? = nil
    var paypalEnabled: Bool = false
    var paypalMeFallback: String? = nil
    var stripeAccountId: String? = nil
    var stripeOnboardingStatus: String? = nil
    var stripeChargesEnabled: Bool = false
    var stripePayoutsEnabled: Bool = false
    var squareEnabled: Bool = false
    var squareLink: String? = nil
    var cashAppEnabled: Bool = false
    var cashAppHandleOrLink: String? = nil
    var venmoEnabled: Bool = false
    var venmoHandleOrLink: String? = nil
    var achEnabled: Bool = false
    var achRecipientName: String? = nil
    var achBankName: String? = nil
    var achAccountLast4: String? = nil
    var achRoutingLast4: String? = nil
    var achInstructions: String? = nil

    var travelBufferMinutes: Int = 15
    var workdayStartMinutes: Int = 9 * 60
    var workdayEndMinutes: Int = 17 * 60

    init(
        id: UUID = UUID(),
        name: String = "",
        isActive: Bool = true,
        defaultTaxRate: Decimal = 0,
        currencyCode: String = "USD",
        defaultInvoiceTemplateKey: String = InvoiceTemplateKey.modern_clean.rawValue,
        paypalMeUrl: String? = nil,
        paypalEnabled: Bool = false,
        paypalMeFallback: String? = nil,
        stripeAccountId: String? = nil,
        stripeOnboardingStatus: String? = nil,
        stripeChargesEnabled: Bool = false,
        stripePayoutsEnabled: Bool = false,
        squareEnabled: Bool = false,
        squareLink: String? = nil,
        cashAppEnabled: Bool = false,
        cashAppHandleOrLink: String? = nil,
        venmoEnabled: Bool = false,
        venmoHandleOrLink: String? = nil,
        achEnabled: Bool = false,
        achRecipientName: String? = nil,
        achBankName: String? = nil,
        achAccountLast4: String? = nil,
        achRoutingLast4: String? = nil,
        achInstructions: String? = nil,
        travelBufferMinutes: Int = 15,
        workdayStartMinutes: Int = 9 * 60,
        workdayEndMinutes: Int = 17 * 60
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.defaultTaxRate = defaultTaxRate
        self.currencyCode = currencyCode
        self.defaultInvoiceTemplateKey = defaultInvoiceTemplateKey
        self.paypalMeUrl = paypalMeUrl
        self.paypalEnabled = paypalEnabled
        self.paypalMeFallback = paypalMeFallback
        self.stripeAccountId = stripeAccountId
        self.stripeOnboardingStatus = stripeOnboardingStatus
        self.stripeChargesEnabled = stripeChargesEnabled
        self.stripePayoutsEnabled = stripePayoutsEnabled
        self.squareEnabled = squareEnabled
        self.squareLink = squareLink
        self.cashAppEnabled = cashAppEnabled
        self.cashAppHandleOrLink = cashAppHandleOrLink
        self.venmoEnabled = venmoEnabled
        self.venmoHandleOrLink = venmoHandleOrLink
        self.achEnabled = achEnabled
        self.achRecipientName = achRecipientName
        self.achBankName = achBankName
        self.achAccountLast4 = achAccountLast4
        self.achRoutingLast4 = achRoutingLast4
        self.achInstructions = achInstructions
        self.travelBufferMinutes = travelBufferMinutes
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
    }
}
