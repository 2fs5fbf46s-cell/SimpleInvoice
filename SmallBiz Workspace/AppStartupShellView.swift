import SwiftUI

struct AppStartupShellView: View {
    let phase: LaunchCoordinator.Phase
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SBWTheme.brandGradient
                    .opacity(0.20)
                    .frame(height: 260)
                    .blur(radius: 42)

                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 18) {
                logo

                VStack(spacing: 6) {
                    Text("SmallBiz Workspace")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Preparing your workspace...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                launchStatus
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 360)
        }
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SBWTheme.brandGradient)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
        .shadow(color: SBWTheme.brandBlue.opacity(0.28), radius: 22, x: 0, y: 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var launchStatus: some View {
        switch phase {
        case .failed(let message):
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.yellow)

                    Text(phase.message)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }

        default:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)

                Text(phase.message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
        }
    }
}
