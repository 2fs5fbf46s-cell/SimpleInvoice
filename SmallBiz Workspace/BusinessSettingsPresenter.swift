import SwiftUI
import SwiftData
import Combine

/// Where the Business settings sheet is opened from.
///
/// Everything More used to hold now lives behind one avatar button, reachable
/// the same way from every tab. This tracks whether that sheet is open and,
/// when it was opened to jump straight to one destination (Setup Payments from
/// a deep link, say), which one.
final class BusinessSettingsPresenter: ObservableObject {
    enum Destination: Hashable {
        case setupPayments
    }

    @Published var isPresented = false
    @Published var pendingDestination: Destination? = nil

    func open(_ destination: Destination? = nil) {
        pendingDestination = destination
        isPresented = true
    }
}

/// The business-avatar button that opens Business settings, placed the same
/// way on every tab's root screen instead of a fifth "More" tab.
struct BusinessAvatarButton: View {
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]) private var profiles: [BusinessProfile]

    private var initials: String {
        let name = profiles.first(where: { $0.businessID == activeBiz.activeBusinessID })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Button {
            Haptics.lightTap()
            businessSettingsPresenter.open()
        } label: {
            Text(initials)
                .font(.scaledSystem(size: 12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(SBWTheme.brandGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Business Settings")
    }
}
