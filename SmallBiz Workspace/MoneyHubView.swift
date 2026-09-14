import SwiftUI

/// Invoices, Estimates and Insights used to be three unrelated screens
/// pretending not to be the same thing: all three are "money owed to you."
/// One segmented control replaces three separate homes; nothing about the
/// screens underneath changes.
struct MoneyHubView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter

    enum Segment: String, CaseIterable, Identifiable {
        case invoices = "Invoices"
        case estimates = "Estimates"
        case expenses = "Expenses"
        case insights = "Insights"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .invoices

    var body: some View {
        VStack(spacing: 0) {
            Picker("Money section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            switch segment {
            case .invoices:
                InvoiceListView(businessID: activeBiz.activeBusinessID)
            case .estimates:
                EstimateListView(businessID: activeBiz.activeBusinessID)
            case .expenses:
                ExpenseListView(businessID: activeBiz.activeBusinessID)
            case .insights:
                BusinessInsightsView(businessID: activeBiz.activeBusinessID)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BusinessAvatarButton { businessSettingsPresenter.open() }
            }
        }
    }
}
