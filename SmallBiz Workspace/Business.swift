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
    var stripeAccountId: String? = nil
    var stripeOnboardingStatus: String? = nil
    var stripeChargesEnabled: Bool? = nil
    var stripePayoutsEnabled: Bool? = nil

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
        stripeAccountId: String? = nil,
        stripeOnboardingStatus: String? = nil,
        stripeChargesEnabled: Bool? = nil,
        stripePayoutsEnabled: Bool? = nil,
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
        self.stripeAccountId = stripeAccountId
        self.stripeOnboardingStatus = stripeOnboardingStatus
        self.stripeChargesEnabled = stripeChargesEnabled
        self.stripePayoutsEnabled = stripePayoutsEnabled
        self.travelBufferMinutes = travelBufferMinutes
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
    }
}
