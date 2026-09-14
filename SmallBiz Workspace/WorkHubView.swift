import SwiftUI

/// Jobs, Bookings and Contracts are all "work you've committed to." Same
/// idea as Money: one segmented control instead of three separate homes.
struct WorkHubView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter

    enum Segment: String, CaseIterable, Identifiable {
        case jobs = "Jobs"
        case bookings = "Bookings"
        case contracts = "Contracts"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .jobs

    var body: some View {
        VStack(spacing: 0) {
            Picker("Work section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            switch segment {
            case .jobs:
                JobsListView(businessID: activeBiz.activeBusinessID)
            case .bookings:
                BookingsListView(businessID: activeBiz.activeBusinessID)
            case .contracts:
                ContractsHomeView(businessID: activeBiz.activeBusinessID)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BusinessAvatarButton { businessSettingsPresenter.open() }
            }
        }
    }
}
