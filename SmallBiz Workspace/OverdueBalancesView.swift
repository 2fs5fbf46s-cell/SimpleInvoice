import SwiftUI

struct OverdueBalancesView: View {
    let businessID: UUID
    let currencyCode: String

    var body: some View {
        OutstandingBalancesView(
            businessID: businessID,
            currencyCode: currencyCode,
            mode: .overdueOnly
        )
    }
}
