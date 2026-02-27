import SwiftUI

struct QuickStartView: View {
    private struct ChecklistItem: Identifiable {
        let id = UUID()
        let title: String
        let action: () -> Void
    }

    private var checklist: [ChecklistItem] {
        [
            ChecklistItem(title: "Add your first client") {
                AppRouteCenter.shared.route(.clientsRoot)
            },
            ChecklistItem(title: "Create and send an invoice") {
                AppRouteCenter.shared.route(.invoicesRoot)
            },
            ChecklistItem(title: "Enable notifications") {
                AppRouteCenter.shared.route(.openAppSettings)
            },
            ChecklistItem(title: "Set up payments") {
                AppRouteCenter.shared.route(.paymentsSetup)
            },
            ChecklistItem(title: "Review the More tools section") {
                AppRouteCenter.shared.route(.moreRoot)
            }
        ]
    }

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
                                Button {
                                    item.action()
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundStyle(SBWTheme.brandBlue)
                                        Text("\(index + 1). \(item.title)")
                                            .font(.subheadline)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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

// How to test:
// 1) Open Help Center -> Quick Start and tap each checklist row.
// 2) Verify Clients/Invoices/More routes switch tab and return tab root safely.
// 3) Verify "Set up payments" routes to More and pushes Setup Payments.
// 4) Verify "Enable notifications" opens app Settings.
