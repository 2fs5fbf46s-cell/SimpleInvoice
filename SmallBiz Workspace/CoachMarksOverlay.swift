import SwiftUI

struct CoachMarkFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func coachMark(id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CoachMarkFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(CoachMarksOverlay.coordinateSpaceName))]
                )
            }
        )
    }
}

struct CoachMarksOverlay: View {
    static let coordinateSpaceName = "sbw.coachmarks.space"

    let steps: [WalkthroughStep]
    let currentIndex: Int
    let frames: [String: CGRect]
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    private var currentStep: WalkthroughStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    private var spotlightRect: CGRect? {
        guard let currentStep else { return nil }
        return frames[currentStep.targetCoachMarkId]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                dimLayer
                tooltip(in: proxy.size)
            }
            .ignoresSafeArea()
            .onTapGesture {
                // Intentionally swallow taps so only controls move the flow.
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var dimLayer: some View {
        Color.black.opacity(0.55)
            .overlay {
                if let rect = spotlightRect {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .frame(width: rect.width + 16, height: rect.height + 16)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: rect)
                }
            }
            .compositingGroup()
    }

    @ViewBuilder
    private func tooltip(in size: CGSize) -> some View {
        if let step = currentStep {
            let total = max(steps.count, 1)
            let stepNumber = min(currentIndex + 1, total)
            let rect = spotlightRect ?? CGRect(x: size.width * 0.5 - 40, y: size.height * 0.45, width: 80, height: 50)
            let cardWidth = min(size.width - 28, 370)
            let prefersAbove = rect.maxY > (size.height * 0.58)
            let yAbove = max(128, rect.minY - 150)
            let yBelow = min(size.height - 126, rect.maxY + 128)
            let y = prefersAbove ? yAbove : yBelow

            VStack(spacing: 0) {
                SBWTheme.brandGradient
                    .opacity(0.08)
                    .blur(radius: 30)
                    .frame(width: cardWidth, height: 14)

                SBWCardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(step.title)
                            .font(.headline)

                        Text(step.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("\(stepNumber) of \(total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if stepNumber > 1 {
                                Button("Back") {
                                    Haptics.lightTap()
                                    onBack()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Skip") {
                                onSkip()
                            }
                            .buttonStyle(.bordered)

                            Button(stepNumber == total ? "Done" : "Next") {
                                Haptics.lightTap()
                                if stepNumber == total {
                                    onDone()
                                } else {
                                    onNext()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SBWTheme.brandBlue)
                        }
                    }
                }
                .frame(width: cardWidth)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title). \(step.message). Step \(stepNumber) of \(total).")
            }
            .position(x: size.width / 2, y: y)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: currentIndex)
        }
    }
}
