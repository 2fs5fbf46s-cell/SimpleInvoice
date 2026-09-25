import SwiftUI
import UIKit
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
///
/// Takes the open action as a plain closure rather than resolving
/// `BusinessSettingsPresenter` via its own `@EnvironmentObject`: this view is
/// only ever instantiated inside a `.toolbar { }` closure, and an environment
/// object read solely inside a button's tap action (never inside `body`
/// itself, the way `activeBiz` is read here via `initials`) can end up bound
/// to whatever environment existed when the toolbar content was first built
/// for layout, not the environment active at tap time — a known SwiftUI
/// toolbar gotcha that crashed this button with "No ObservableObject of type
/// BusinessSettingsPresenter found" on every tap. Forwarding the action in
/// from the caller's own body sidesteps it entirely.
struct BusinessAvatarButton: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]) private var profiles: [BusinessProfile]
    var onTap: () -> Void

    private var profile: BusinessProfile? {
        profiles.first(where: { $0.businessID == activeBiz.activeBusinessID })
    }

    private var initials: String {
        let name = profile?.name
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
            onTap()
        } label: {
            // The business's logo, or its initials on its own color: this is
            // the business, not the app.
            Group {
                if let data = profile?.logoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(initials)
                        .font(.scaledSystem(size: 12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BrandColor.color(BrandColor.readableOnWhite(BrandColor.resolved(profile?.brandColorHex))))
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Business Settings")
        .coachMark(id: "walkthrough.avatar")
    }
}
