import SwiftUI
import UIKit

struct HelpCenterView: View {
    @Environment(\.openURL) private var openURL
    @State private var showSupportSheet = false
    @State private var showSupportFallbackAlert = false

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
                                contactSupportTapped()
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
        .alert("Contact Support", isPresented: $showSupportFallbackAlert) {
            Button("Copy Email") {
                UIPasteboard.general.string = "support@smallbizworkspace.com"
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("support@smallbizworkspace.com")
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

    private func contactSupportTapped() {
        let subject = "SmallBiz Workspace Support"
        let body = "App Version: \(versionLabel)"
        let mailto = "mailto:support@smallbizworkspace.com?subject=\(urlEncode(subject))&body=\(urlEncode(body))"

        guard let url = URL(string: mailto) else {
            showSupportSheet = true
            return
        }

        openURL(url) { accepted in
            if accepted == false {
                showSupportFallbackAlert = true
            }
        }
    }

    private func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}

// How to test:
// 1) Open Help Center and tap Contact Support.
// 2) Verify mail compose opens with prefilled subject/body; if unavailable, alert appears with Copy Email.
// 3) Verify Privacy Policy and User Agreement open correctly.
