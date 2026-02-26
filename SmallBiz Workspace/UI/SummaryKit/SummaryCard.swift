import SwiftUI

extension SummaryKit {
    struct SummaryCard<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
