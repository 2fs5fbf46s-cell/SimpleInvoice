import SwiftUI
import SwiftData

struct RootGateView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var businesses: [Business]
    @AppStorage(OnboardingState.completeKey) private var hasCompletedOnboarding: Bool = false

    private var shouldShowOnboarding: Bool {
        businesses.isEmpty || !hasCompletedOnboarding
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingFlowView()
            } else {
                AppTabView()
            }
        }
        .task(id: gateTaskKey) {
            await syncActiveBusinessSelection()
        }
    }

    private var gateTaskKey: String {
        "\(shouldShowOnboarding)-\(businesses.count)-\(hasCompletedOnboarding)"
    }

    @MainActor
    private func syncActiveBusinessSelection() async {
        if shouldShowOnboarding {
            activeBiz.clearActiveBusiness()
            return
        }

        if let selected = activeBiz.activeBusinessID,
           businesses.contains(where: { $0.id == selected }) {
            return
        }

        guard let first = businesses.first else {
            activeBiz.clearActiveBusiness()
            return
        }
        activeBiz.setActiveBusiness(first.id)
    }
}
