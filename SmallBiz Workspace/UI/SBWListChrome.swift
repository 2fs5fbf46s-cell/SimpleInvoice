import SwiftUI

/// The parts every list screen was building for itself.
///
/// Invoices, Estimates, Clients, Jobs, Bookings and Inventory all do the same
/// job — search, filter, rows, empty state — and each had grown its own version.
/// The visible costs were a filter row that sliced its last chip through the
/// middle of a letter on two screens, and an empty state whose primary action
/// was styled `.buttonStyle(.plain)` everywhere, so the single most important
/// control on the screen read as a caption.
///
/// These two components are the shared versions.

// MARK: - Filter chips

/// One row of single-choice filters, on the screen's background rather than
/// in a box of its own.
///
/// When the chips don't fit, the row scrolls and fades out at the trailing
/// edge. Bookings and Jobs once scrolled with no fade, so "Cancelled" showed
/// as "Car" cut mid-glyph and read as a rendering bug; this then wrapped
/// instead, which left a lone "All" on a second line and cost a row of
/// screen. In a List, give it a Section of its own: its row background is
/// clear.
struct SBWFilterChips<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal, showsIndicators: false) {
                chips.padding(.trailing, 28)
            }
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    Haptics.lightTap()
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? AnyShapeStyle(SBWTheme.brand)
                                    : AnyShapeStyle(Color.primary.opacity(0.10))
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .fixedSize()
    }
}

// MARK: - Empty state

/// What a list shows when it has nothing, with an action that looks like one.
struct SBWEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.scaledSystem(size: 40, weight: .regular, relativeTo: .largeTitle))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button {
                    Haptics.lightTap()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brand)
                .padding(.top, 2)
            }

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle) {
                    Haptics.lightTap()
                    secondaryAction()
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(SBWTheme.brand)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

/// Copy for an empty list that tells the truth about *why* it is empty.
///
/// Invoices and Estimates said "Try changing the filter or create a new invoice"
/// even with the All filter selected and zero records, where no filter change
/// could possibly help.
enum SBWEmptyStateCopy {
    static func message(noun: String, pluralNoun: String, isFiltered: Bool) -> String {
        isFiltered
            ? "No \(pluralNoun) match this filter. Try a different one, or clear your search."
            : "You haven't created any \(pluralNoun) yet. Your first \(noun) will show up here."
    }
}
