import SwiftUI

struct ToolbarCircleButton: View {
    let systemImage: String
    /// What the control does, spoken by VoiceOver. Required: an icon-only button
    /// with no label announces as just "Button".
    let accessibilityLabel: String
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                // Scales with Dynamic Type instead of staying at 18pt.
                .font(.scaledSystem(size: 18, weight: .semibold, relativeTo: .body))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(.plain)          // ✅ removes the system “pill” background
        .contentShape(Circle())       // ✅ keeps tap target circular
    }
}
