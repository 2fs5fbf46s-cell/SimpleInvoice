import SwiftUI
import UIKit

struct HelpCenterView: View {
    @Environment(\.openURL) private var openURL
    @State private var showSupportSheet = false
    @State private var showSupportFallbackAlert = false
    @State private var searchText = ""

    private var filteredFAQCategories: [FAQCategory] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return FAQCategory.all }
        return FAQCategory.all.compactMap { category in
            let items = category.items.filter {
                $0.question.lowercased().contains(q) || $0.answer.lowercased().contains(q)
            }
            return items.isEmpty ? nil : FAQCategory(title: category.title, items: items)
        }
    }

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

                    VStack(alignment: .leading, spacing: 14) {
                        Text("FREQUENTLY ASKED QUESTIONS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                            .padding(.horizontal, 4)

                        if filteredFAQCategories.isEmpty {
                            SBWCardContainer {
                                Text("No results for \u{201c}\(searchText)\u{201d}.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            }
                        } else {
                            ForEach(filteredFAQCategories) { category in
                                CreateSectionCard(title: category.title) {
                                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 {
                                            Divider().opacity(0.6)
                                        }
                                        FAQRow(item: item)
                                    }
                                }
                            }
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
        .navigationTitle("Help & About")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .searchable(text: $searchText, prompt: "Search help")
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

private struct FAQRow: View {
    let item: FAQItem
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(item.answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.trailing, 4)
        } label: {
            Text(item.question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .tint(.secondary)
    }
}

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private struct FAQCategory: Identifiable {
    let id = UUID()
    let title: String
    let items: [FAQItem]

    static let all: [FAQCategory] = [
        FAQCategory(title: "Getting Started", items: [
            FAQItem(
                question: "What does the Quick Start checklist track?",
                answer: "Four steps: add your first client, send an invoice, turn on notifications, and set up a payment method. The Dashboard shows how many you've completed and links straight to the next one."
            ),
            FAQItem(
                question: "How do I switch between businesses?",
                answer: "Open Business Profile, expand Advanced, and choose Switch Business. Everything in the app — invoices, clients, contracts — is scoped to whichever business is active."
            ),
            FAQItem(
                question: "What's the Create button for?",
                answer: "The + tab in the middle of the bar is a shortcut to start anything new — an invoice, estimate, contract, booking, client or job — grouped by what you're trying to do."
            )
        ]),
        FAQCategory(title: "Invoices & Estimates", items: [
            FAQItem(
                question: "Why is Send disabled on my invoice?",
                answer: "An invoice needs at least one line item with an amount before it can go out. Add one under Line Items on the invoice screen, and Send becomes active."
            ),
            FAQItem(
                question: "What's the difference between an invoice and an estimate?",
                answer: "An estimate is a quote a client can accept or decline before any work happens. Once accepted, you convert it into an invoice from the same screen — the line items carry over."
            ),
            FAQItem(
                question: "How do invoice numbers get assigned?",
                answer: "Automatically, in the form PREFIX-YEAR-NUMBER (for example SI-2026-001). The prefix comes from your Business Profile and can be changed there."
            ),
            FAQItem(
                question: "Can I reuse services or products I bill often?",
                answer: "Yes — save them once under Saved Items (in More), then add them straight into any invoice or estimate instead of retyping the description and price each time."
            )
        ]),
        FAQCategory(title: "Payments", items: [
            FAQItem(
                question: "Which payment methods can I accept?",
                answer: "Stripe, PayPal, Square, Cash App, Venmo and ACH, each configured separately under Setup Payments."
            ),
            FAQItem(
                question: "Do I have to enable every payment method?",
                answer: "No. Enable only the ones you actually want to offer — each stays clearly marked Disabled until you turn it on."
            ),
            FAQItem(
                question: "Why does the app say it can't check my Stripe or PayPal status?",
                answer: "This device isn't signed in for the active business yet, so it can't reach that provider's status. Reopen the app to sign in again, and contact support if it keeps happening."
            )
        ]),
        FAQCategory(title: "Contracts", items: [
            FAQItem(
                question: "Can I edit a contract after a client signs it?",
                answer: "No — the contract body locks the moment it's signed, and the status picker won't even offer Signed as an option to select by hand. This protects the record of what your client actually agreed to. If terms change, send a new contract."
            ),
            FAQItem(
                question: "How does a client sign a contract?",
                answer: "Open the contract and use the \u{2026} menu to Open in Client Portal, or share the portal link from the contract summary. They review and sign from there."
            ),
            FAQItem(
                question: "What's the Music Split Sheet?",
                answer: "A guided, structured form for splitting songwriting or production credit and royalties between contributors, available from Create From Template on the Contracts screen."
            )
        ]),
        FAQCategory(title: "Clients & Client Portal", items: [
            FAQItem(
                question: "What happens to old invoices when I delete a client?",
                answer: "The invoices stay — they keep the name and address the client had at the time, so your records don't change. Only the client record itself is removed, and you'll be shown how many invoices reference them before you confirm."
            ),
            FAQItem(
                question: "What is the Client Portal?",
                answer: "A secure page where a specific client can view their invoices, contracts and shared files without needing an account. Turn it on per client from the client's edit screen."
            ),
            FAQItem(
                question: "What does \u{201c}Portal On\u{201d} mean in the Clients filter?",
                answer: "It shows only clients who currently have portal access enabled, so you can see at a glance who can log in to view their documents."
            )
        ]),
        FAQCategory(title: "Jobs & Bookings", items: [
            FAQItem(
                question: "What's the difference between Jobs and Bookings?",
                answer: "Jobs are work you're tracking internally. Bookings are requests coming in from your public booking page that need your approval before they become a job."
            ),
            FAQItem(
                question: "Can a deposit be more than the booking total?",
                answer: "No — a deposit can equal the full booking total but never exceed it. The app rejects anything higher before it reaches the client."
            )
        ]),
        FAQCategory(title: "Your Website", items: [
            FAQItem(
                question: "What is the Website screen for?",
                answer: "It builds a public page for your business — hero image, services, team, gallery — that customers can view and book from. Preview it before publishing."
            ),
            FAQItem(
                question: "Where do customers actually find my site?",
                answer: "At the Site Address you set on the Website screen, or at a custom domain if you've connected one. Publishing makes it visible on the internet, so you'll be asked to confirm first."
            )
        ]),
        FAQCategory(title: "Troubleshooting", items: [
            FAQItem(
                question: "The app says this device isn't signed in for my business. What do I do?",
                answer: "Reopen the app to sign in again. If it keeps happening after that, contact support below so we can look into it."
            ),
            FAQItem(
                question: "How do I reach support?",
                answer: "Use Contact Support below — it opens an email pre-filled with your app version, or shows the support address to copy if you don't have Mail set up."
            )
        ])
    ]
}

// How to test:
// 1) Open Help Center and tap Contact Support.
// 2) Verify mail compose opens with prefilled subject/body; if unavailable, alert appears with Copy Email.
// 3) Verify Privacy Policy and User Agreement open correctly.
// 4) Search the FAQ (e.g. "deposit", "portal") and verify matching categories/questions filter correctly.
// 5) Expand a few FAQ rows and confirm they collapse/expand independently.
