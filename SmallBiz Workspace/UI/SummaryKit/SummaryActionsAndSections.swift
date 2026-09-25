import SwiftUI

extension SummaryKit {
struct PrimaryActionRow: View {
    enum Prominence {
        case primary
        case secondary
    }

    struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let prominence: Prominence
        let isEnabled: Bool
        let action: () -> Void

        init(
            title: String,
            systemImage: String,
            role: ButtonRole? = nil,
            prominence: Prominence = .primary,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.role = role
            self.prominence = prominence
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    let actions: [ActionItem]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Icon above a label that may wrap to two lines: side by side, a label
    // like "Create Estimate" only got a third or a quarter of the row and
    // truncated to "C…". At accessibility text sizes even stacked tiles
    // don't fit four across, so they drop to two columns.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(actions) { item in
                    actionButton(for: item)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(actions) { item in
                    actionButton(for: item)
                }
            }
            // Every tile matches the tallest, whether its label took one
            // line or two.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actionButton(for item: ActionItem) -> some View {
        let label = VStack(spacing: 4) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 4)

        switch item.prominence {
        case .primary:
            Button(role: item.role, action: item.action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(SBWTheme.brand)
                .disabled(!item.isEnabled)
        case .secondary:
            Button(role: item.role, action: item.action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(SBWTheme.brand)
                .disabled(!item.isEnabled)
        }
    }
}

struct CollapsibleSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        SummaryKit.SummaryCard {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.4)
                content
            }
        }
    }
}
}
