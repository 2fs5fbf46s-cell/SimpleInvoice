import SwiftUI

extension SummaryKit {
struct PrimaryActionRow: View {
    struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.role = role
            self.action = action
        }
    }

    let actions: [ActionItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { item in
                Button(role: item.role, action: item.action) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                        Text(item.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
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
                        .font(.system(size: 14, weight: .semibold))
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
