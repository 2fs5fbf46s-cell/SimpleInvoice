import SwiftUI

struct QuickStartView: View {
    private let checklist: [String] = [
        "Add your first client",
        "Create and send an invoice",
        "Enable notifications",
        "Set up payments",
        "Review the More tools section"
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 12) {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quick Start")
                                .font(.headline)
                            Text("Use this checklist to get your workspace fully ready.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(SBWTheme.brandBlue)
                                    Text("\(index + 1). \(item)")
                                        .font(.subheadline)
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
    }
}
