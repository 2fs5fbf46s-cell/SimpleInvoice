import Foundation
import SwiftData

@Model
final class Business {
    var id: UUID = UUID()
    var name: String = ""
    var isActive: Bool = true

    var defaultTaxRate: Decimal = 0
    var currencyCode: String = "USD"

    var paypalMeUrl: String? = nil

    var travelBufferMinutes: Int = 15
    var workdayStartMinutes: Int = 9 * 60
    var workdayEndMinutes: Int = 17 * 60

    init(
        id: UUID = UUID(),
        name: String = "",
        isActive: Bool = true,
        defaultTaxRate: Decimal = 0,
        currencyCode: String = "USD",
        paypalMeUrl: String? = nil,
        travelBufferMinutes: Int = 15,
        workdayStartMinutes: Int = 9 * 60,
        workdayEndMinutes: Int = 17 * 60
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.defaultTaxRate = defaultTaxRate
        self.currencyCode = currencyCode
        self.paypalMeUrl = paypalMeUrl
        self.travelBufferMinutes = travelBufferMinutes
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
    }
}
