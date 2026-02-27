import SwiftUI

struct OverdueBalancesView: View {
    let businessID: UUID

    var body: some View {
        OutstandingBalancesView(
            businessID: businessID,
            mode: .overdueOnly
        )
    }
}
