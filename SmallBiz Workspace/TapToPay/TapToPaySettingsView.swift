//
//  TapToPaySettingsView.swift
//  SmallBiz Workspace
//

import SwiftData
import SwiftUI

/// Business → Tap to Pay on iPhone: whether this iPhone is ready, setting it
/// up outside checkout (3.6), and Apple's how-to any time (4.3).
struct TapToPaySettingsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]
    @ObservedObject private var reader = TapToPayReader.shared

    @State private var showSetUp = false
    @State private var showHowTo = false

    private var profile: BusinessProfile? { profiles.first { $0.businessID == activeBiz.activeBusinessID } }
    private var business: Business? { businesses.first { $0.id == activeBiz.activeBusinessID } }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("This iPhone")
                    Spacer()
                    statusBadge
                }
                if case .preparing(let progress) = reader.status, let progress {
                    ProgressView(value: progress)
                }
            } footer: {
                Text(statusDetail)
            }

            Section {
                if !isReady {
                    Button("Set Up Tap to Pay on iPhone") { showSetUp = true }
                }
                Button("How to Accept Payments") {
                    Task { if await !TapToPayEducation.present() { showHowTo = true } }
                }
            } footer: {
                Text("Accept contactless cards, Apple Pay and other digital wallets right on this iPhone, with no extra hardware. Payments go to your Stripe account. Requires iPhone XS or later.")
            }

            // Where the launch push's and announcement's "Terms apply." lead.
            Section {
            } footer: {
                TapToPayDisclaimer.text
            }
        }
        .navigationTitle("Tap to Pay on iPhone")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .task { await reader.prepare(business: business, profile: profile) }
        .sheet(isPresented: $showSetUp) {
            NavigationStack {
                TapToPaySetupFlow(business: business, profile: profile) { _ in showSetUp = false }
                    .navigationTitle("Tap to Pay on iPhone")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSetUp = false } }
                    }
            }
        }
        .sheet(isPresented: $showHowTo) { TapToPayHowToView() }
    }

    private var isReady: Bool {
        if case .ready = reader.status { return true }
        return false
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch reader.status {
            case .ready: return ("Ready", SBWTheme.success)
            case .preparing: return ("Getting ready", SBWTheme.attention)
            case .checking: return ("Checking…", .secondary)
            case .unsupported: return ("Not supported", .secondary)
            default: return ("Not set up", SBWTheme.attention)
            }
        }()
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var statusDetail: String {
        switch reader.status {
        case .ready: return "Ready to take payments. Open an invoice and tap Tap to Pay on iPhone."
        case .preparing: return "Apple is setting this iPhone up to accept payments. Tap to Pay on iPhone isn't ready until it finishes."
        case .checking: return ""
        case .unsupported(let text), .problem(let text): return text
        case .needsStripe: return "Finish setting up Stripe in Payment Methods first."
        case .needsAddress: return "Add your business address to set up Tap to Pay on iPhone."
        case .needsLocationPermission(let denied):
            return denied
                ? "Location is off for SmallBiz Workspace. Turn it on in Settings to take payments."
                : "Set up to accept Apple's terms and allow location."
        case .notSetUp: return "Set up once to accept Apple's Tap to Pay on iPhone terms for your business."
        }
    }
}

/// The one-time announcement (3.1–3.3, 6.2): full screen, once per business
/// on this iPhone, to owners who could use Tap to Pay but haven't set it up.
///
/// Apple's "Hero" in-app banner from the Tap to Pay on iPhone Marketing
/// Toolkit (In-App Banners › Hero › Card to iPhone, 9x16), laid out as the
/// template is. The artwork is Apple's, unaltered; the headline and body are
/// the template's copy word for word, set as text so they scale with Dynamic
/// Type, and the template's "[Your CTA]" placeholder is the real button.
/// Custom marketing art or copy isn't allowed here.
struct TapToPayAnnouncementView: View {
    let business: Business?
    let profile: BusinessProfile?
    let onClose: () -> Void

    @State private var settingUp = false
    @State private var showTerms = false

    var body: some View {
        NavigationStack {
            if settingUp {
                TapToPaySetupFlow(business: business, profile: profile) { _ in onClose() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onClose) }
                    }
            } else {
                hero
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    /// The template is black on white in both appearances, like the artwork.
    private var hero: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tap to Pay\non iPhone")
                    .font(.scaledSystem(size: 38, weight: .bold, relativeTo: .largeTitle))
                    .padding(.horizontal, 36)
                    .padding(.top, 56)
                    .accessibilityAddTraits(.isHeader)

                Image("TapToPayHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Accept physical debit and credit cards as well as Apple Pay and other digital wallets. Right on your iPhone.")
                        .font(.scaledSystem(size: 17, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)

                    Button { settingUp = true } label: {
                        Text("Set Up Tap to Pay on iPhone")
                            .font(.scaledSystem(size: 17, relativeTo: .body))
                            .padding(.vertical, 11)
                            .padding(.horizontal, 22)
                            .overlay(Capsule().strokeBorder(.black, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { showTerms = true } label: {
                        Text("Terms apply.")
                            .font(.scaledSystem(size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color(white: 0.45))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 32)
            }
            .foregroundStyle(.black)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.scaledSystem(size: 15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color(white: 0.3))
                    .padding(9)
                    .background(Circle().fill(Color(white: 0.93)))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Not Now")
            .padding(.trailing, 12)
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showTerms) { TapToPayDisclaimer.Sheet() }
    }

    static func defaultsKey(_ businessID: UUID) -> String { "tapToPay.announced.\(businessID.uuidString)" }

    static func wasShown(for businessID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: defaultsKey(businessID))
    }

    static func markShown(for businessID: UUID) {
        UserDefaults.standard.set(true, forKey: defaultsKey(businessID))
    }
}

/// Puts the announcement up once Tap to Pay is offered but not set up.
struct TapToPayAnnouncementHost: ViewModifier {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]
    @ObservedObject private var reader = TapToPayReader.shared
    @State private var showing = false

    private var business: Business? { businesses.first { $0.id == activeBiz.activeBusinessID } }
    private var profile: BusinessProfile? { profiles.first { $0.businessID == activeBiz.activeBusinessID } }

    func body(content: Content) -> some View {
        content
            .onChange(of: reader.status) { _, status in
                guard let id = business?.id, !TapToPayAnnouncementView.wasShown(for: id) else { return }
                switch status {
                case .notSetUp, .needsAddress, .needsLocationPermission(denied: false):
                    TapToPayAnnouncementView.markShown(for: id)
                    showing = true
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: $showing) {
                TapToPayAnnouncementView(business: business, profile: profile) { showing = false }
            }
    }
}

extension View {
    func tapToPayAnnouncement() -> some View { modifier(TapToPayAnnouncementHost()) }
}

/// Apple's full disclaimer, and its Apple Pay one, from the Tap to Pay on
/// iPhone Marketing Guide (September 2026), word for word. A short "Terms
/// apply." must lead to these.
enum TapToPayDisclaimer {
    static let full = "Tap to Pay on iPhone requires a supported payment app and the latest version of iOS. Update to the latest version by going to Settings > General > Software Update. Some contactless cards may not be accepted by your payment app. Transaction limits may apply. Tap to Pay on iPhone is not available in all markets. For Tap to Pay on iPhone countries and regions, see https://developer.apple.com/tap-to-pay/regions/."
    static let applePay = "Apple Pay is a service provided by Apple Payments Services LLC, a subsidiary of Apple Inc. Neither Apple Inc. nor Apple Payments Services LLC is a bank. Any card used in Apple Pay is offered by the card issuer."

    static var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(full)
            Text(applePay)
        }
    }

    struct Sheet: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    TapToPayDisclaimer.text
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Terms")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
