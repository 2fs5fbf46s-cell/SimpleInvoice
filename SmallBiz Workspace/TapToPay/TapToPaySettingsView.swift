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
/// Placeholder art and copy: before release this must be the "Hero" in-app
/// banner from Apple's Tap to Pay on iPhone Marketing Toolkit — custom
/// marketing art isn't allowed.
struct TapToPayAnnouncementView: View {
    let business: Business?
    let profile: BusinessProfile?
    let onClose: () -> Void

    @State private var settingUp = false

    var body: some View {
        NavigationStack {
            Group {
                if settingUp {
                    TapToPaySetupFlow(business: business, profile: profile) { _ in onClose() }
                } else {
                    VStack(spacing: 18) {
                        Spacer()
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.scaledSystem(size: 88, relativeTo: .largeTitle))
                            .foregroundStyle(SBWTheme.brand)
                        Text("Tap to Pay on iPhone")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Accept contactless cards, Apple Pay and other digital wallets right on your iPhone. No extra hardware needed.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                        Button("Set Up Tap to Pay on iPhone") { settingUp = true }
                            .sbwProminentButton()
                        Button("Not Now", action: onClose)
                            .buttonStyle(.borderless)
                    }
                    .padding(24)
                }
            }
            .toolbar {
                if settingUp {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onClose) }
                }
            }
        }
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
