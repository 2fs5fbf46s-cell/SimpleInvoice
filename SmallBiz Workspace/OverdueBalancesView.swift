import SwiftUI

struct OverdueBalancesView: View {
    let businessID: UUID
    let currencyCode: String

    var body: some View {
        OutstandingBalancesView(
            businessID: businessID,
            mode: .overdueOnly,
            currencyCode: currencyCode
        )
    }
}
