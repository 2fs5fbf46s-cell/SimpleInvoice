import SwiftUI

struct HelpCenterView: View {
    @Environment(\.openURL) private var openURL
    @State private var showSupportSheet = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 12) {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tutorial")
                                .font(.headline)

                            Button {
                                Haptics.lightTap()
                                WalkthroughState.requestRun()
                            } label: {
                                Label("Run Walkthrough", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SBWTheme.brandBlue)

                            NavigationLink {
                                QuickStartView()
                            } label: {
                                Label("View Quick Start", systemImage: "list.bullet")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Support")
                                .font(.headline)

                            supportRow(title: "Contact Support", systemImage: "envelope") {
                                if let url = URL(string: "mailto:support@smallbizworkspace.com") {
                                    openURL(url)
                                } else {
                                    showSupportSheet = true
                                }
                            }

                            supportRow(title: "Privacy Policy", systemImage: "hand.raised") {
                                if let url = URL(string: "https://smallbizworkspace-portal-backend.vercel.app/privacy") {
                                    openURL(url)
                                }
                            }

                            supportRow(title: "User Agreement", systemImage: "doc.text") {
                                if let url = URL(string: "https://smallbizworkspace-portal-backend.vercel.app/terms") {
                                    openURL(url)
                                }
                            }
                        }
                    }

                    SBWCardContainer {
                        HStack {
                            Text("Version")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(versionLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Help Center")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSupportSheet) {
            NavigationStack {
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    SBWTheme.headerWash()
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Support")
                                .font(.headline)
                            Text("Email us at support@smallbizworkspace.com")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("Contact")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSupportSheet = false }
                    }
                }
            }
        }
    }

    private var versionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func supportRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(SBWTheme.brandBlue)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
