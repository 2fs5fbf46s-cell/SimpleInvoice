import SwiftUI

/// A filled action button that stays readable inside a List row.
///
/// With `.borderedProminent` in a List row, a Label's icon takes the
/// list's accent instead of the button's white — invisible
/// on a blue button and wrong on a green one — and no foreground modifier
/// reaches it. Drawing the fill ourselves keeps icon and text white.
struct SBWProminentButtonStyle: ButtonStyle {
    var tint: Color = SBWTheme.brandFill
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(WhiteIconLabelStyle())
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .tint(Color.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(Capsule().fill(tint.opacity(isEnabled ? 1 : 0.4)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Lays the label out itself so the list row's icon tint can't reach it.
private struct WhiteIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(Color.white)
            configuration.title
                .foregroundStyle(Color.white)
        }
    }
}

extension View {
    func sbwProminentButton(_ tint: Color = SBWTheme.brandFill) -> some View {
        buttonStyle(SBWProminentButtonStyle(tint: tint))
    }
}
