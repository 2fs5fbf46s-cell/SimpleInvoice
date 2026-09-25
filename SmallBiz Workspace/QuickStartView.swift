import SwiftUI
import SwiftData

struct QuickStartView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @State private var checklist = QuickStartChecklist()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 12) {
                    SBWCardContainer {
                        QuickStartProgressHeader(checklist: checklist)
                    }

                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(QuickStartChecklist.Step.allCases.enumerated()), id: \.element.id) { index, step in
                                QuickStartRow(
                                    step: step,
                                    isComplete: checklist.isComplete(step),
                                    isNext: checklist.nextStep == step
                                ) {
                                    AppRouteCenter.shared.route(step.route)
                                }

                                if index < QuickStartChecklist.Step.allCases.count - 1 {
                                    Divider().padding(.leading, 34)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Quick Start")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .task(id: activeBiz.activeBusinessID) { await refresh() }
    }

    @MainActor
    private func refresh() async {
        let status = await NotificationManager().getAuthorizationStatus()
        checklist = QuickStartChecklist.fromStoredData(
            businessID: activeBiz.activeBusinessID,
            context: modelContext,
            notificationsEnabled: QuickStartChecklist.notificationsAreEnabled(status: status)
        )
    }
}

// MARK: - Pieces

struct QuickStartProgressHeader: View {
    let checklist: QuickStartChecklist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(checklist.isFullyComplete ? "You're all set" : "Quick Start")
                    .font(.headline)
                Spacer()
                Text("\(checklist.completedCount) of \(checklist.totalCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(checklist.completedCount) of \(checklist.totalCount) steps complete")
            }

            ProgressView(
                value: Double(checklist.completedCount),
                total: Double(checklist.totalCount)
            )
            .tint(SBWTheme.success)
            .accessibilityHidden(true)

            Text(
                checklist.isFullyComplete
                    ? "Your workspace is ready to run."
                    : "A few steps to get your workspace earning."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct QuickStartRow: View {
    let step: QuickStartChecklist.Step
    let isComplete: Bool
    let isNext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isComplete ? SBWTheme.success : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(isNext ? .semibold : .regular))
                        .foregroundStyle(isComplete ? .secondary : .primary)
                        .strikethrough(isComplete, color: .secondary)
                        .multilineTextAlignment(.leading)

                    if !isComplete {
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if !isComplete {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isComplete)
        .accessibilityLabel(step.title)
        .accessibilityValue(isComplete ? "Done" : "Not done")
        .accessibilityHint(isComplete ? "" : step.detail)
    }
}
