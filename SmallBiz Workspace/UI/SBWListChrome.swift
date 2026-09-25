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

/// A row of single-choice filters that wraps instead of clipping.
///
/// Bookings and Jobs scrolled theirs horizontally with no fade and no partial
/// chip showing, so "Cancelled" appeared as "Car" cut mid-glyph and read as a
/// rendering bug rather than as something you could scroll.
struct SBWFilterChips<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        FlowLayout(spacing: 8) {
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

/// Lays children left to right, wrapping to the next line when they run out of
/// room — which is the whole point, given the labels these carry.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var lineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].isEmpty ? size.width : lineWidth + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([size])
                lineWidth = size.width
            } else {
                rows[rows.count - 1].append(size)
                lineWidth = needed
            }
        }

        var height: CGFloat = 0
        for row in rows {
            let tallest: CGFloat = row.map(\.height).max() ?? 0
            height += tallest
        }
        let gaps = CGFloat(max(0, rows.count - 1)) * spacing
        height += gaps

        var widest: CGFloat = 0
        for row in rows {
            var rowWidth: CGFloat = 0
            for size in row { rowWidth += size.width }
            rowWidth += CGFloat(max(0, row.count - 1)) * spacing
            widest = max(widest, rowWidth)
        }

        return CGSize(width: min(widest, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
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
