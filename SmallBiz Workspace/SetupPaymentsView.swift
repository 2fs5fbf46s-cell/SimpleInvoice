import SwiftUI
import SwiftData

struct SetupPaymentsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var businesses: [Business]

    @State private var business: Business?
    @State private var stripeStatus: StripeConnectStatus?
    @State private var isLoadingStripe = false
    @State private var isStartingStripe = false
    @State private var stripeError: String?
    @State private var showStripeError = false
    @State private var stripeURL: URL?
    @State private var showStripeSafari = false
    @State private var awaitingStripeReturn = false

    @State private var isLoadingPayPalPlatform = false
    @State private var payPalPlatformEnabled = false
    @State private var payPalError: String?
    @State private var showPayPalError = false

    @State private var showingACHSheet = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let business {
                        stripeCard(business)
                        payPalCard(business)
                        squareCard(business)
                        cashAppCard(business)
                        venmoCard(business)
                        achCard(business)
                    } else {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Setup Payments")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            resolveBusiness()
            Task { await refreshStripeStatus() }
            Task { await refreshPayPalPlatformStatus() }
        }
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            resolveBusiness()
            Task { await refreshStripeStatus() }
            Task { await refreshPayPalPlatformStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if awaitingStripeReturn {
                awaitingStripeReturn = false
                Task { await refreshStripeStatus() }
            }
        }
        .sheet(isPresented: $showStripeSafari) {
            if let stripeURL {
                SafariView(url: stripeURL) {
                    showStripeSafari = false
                    awaitingStripeReturn = true
                }
            } else {
                Text("Unable to open Stripe onboarding.")
            }
        }
        .sheet(isPresented: $showingACHSheet) {
            if let business {
                achEditorSheet(for: business)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Stripe Error", isPresented: $showStripeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(stripeError ?? "Something went wrong.")
        }
        .alert("PayPal Error", isPresented: $showPayPalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(payPalError ?? "Something went wrong.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup Payments")
                .font(.title2.weight(.bold))
            Text("Simple, fast and secure way to accept payments")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stripeCard(_ business: Business) -> some View {
        let status = stripeState
        return providerCard(
            logo: "stripe_logo",
            title: "Stripe Connect",
            description: "Accept cards and wallet payments with connected payouts.",
            methodChips: ["Visa", "Mastercard", "Apple Pay"],
            feeNote: "Fees vary by region and card type.",
            status: status.label,
            primaryTitle: isStartingStripe ? "Opening…" : (status.isConnected ? "Manage Stripe" : "Connect with Stripe"),
            secondaryTitle: "Refresh Status",
            primaryDisabled: isStartingStripe || isLoadingStripe,
            secondaryDisabled: isLoadingStripe || isStartingStripe
        ) {
            await startStripe()
        } onSecondaryTap: {
            await refreshStripeStatus()
        }
    }

    private func payPalCard(_ business: Business) -> some View {
        providerCard(
            logo: "paypal_logo",
            title: "PayPal",
            description: "Platform-first PayPal checkout with optional fallback link.",
            methodChips: ["PayPal", "Cards"],
            feeNote: "PayPal fees apply per transaction.",
            status: payPalPlatformEnabled ? "Enabled" : "Not connected",
            primaryTitle: payPalPlatformEnabled ? "Enabled" : (isLoadingPayPalPlatform ? "Checking…" : "Check Status"),
            secondaryTitle: nil,
            primaryDisabled: isLoadingPayPalPlatform,
            secondaryDisabled: true
        ) {
            await refreshPayPalPlatformStatus()
        } onSecondaryTap: { }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Divider()
                TextField(
                    "PayPal.me fallback (optional)",
                    text: Binding(
                        get: { business.paypalMeFallback ?? "" },
                        set: {
                            business.paypalMeFallback = normalizeURL($0)
                            business.paypalMeUrl = business.paypalMeFallback
                            save()
                        }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func squareCard(_ business: Business) -> some View {
        providerCard(
            logo: "square_logo",
            title: "Square",
            description: "Manual Square link with payment reconciliation approval.",
            methodChips: ["Cards", "Wallets"],
            feeNote: "Use your hosted Square payment link.",
            status: business.squareEnabled ? "Enabled" : "Not connected",
            primaryTitle: "Enable Square",
            secondaryTitle: nil,
            primaryDisabled: false,
            secondaryDisabled: true
        ) {
            business.squareEnabled = true
            business.squareLink = normalizeURL(business.squareLink)
            save()
        } onSecondaryTap: { }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Divider()
                Toggle("Enable Square", isOn: Binding(
                    get: { business.squareEnabled },
                    set: {
                        business.squareEnabled = $0
                        save()
                    }
                ))
                TextField("https://square.link/...", text: Binding(
                    get: { business.squareLink ?? "" },
                    set: {
                        business.squareLink = normalizeURL($0)
                        save()
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func cashAppCard(_ business: Business) -> some View {
        providerCard(
            logo: "cashapp_logo",
            title: "Cash App",
            description: "Accept Cash App with manual payment reconciliation.",
            methodChips: ["Cash App"],
            feeNote: "Customers can pay with your Cash App profile.",
            status: business.cashAppEnabled ? "Enabled" : "Not connected",
            primaryTitle: "Enable Cash App",
            secondaryTitle: nil,
            primaryDisabled: false,
            secondaryDisabled: true
        ) {
            business.cashAppEnabled = true
            business.cashAppHandleOrLink = normalizeCashAppInput(business.cashAppHandleOrLink ?? "")
            save()
        } onSecondaryTap: { }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Divider()
                Toggle("Enable Cash App", isOn: Binding(
                    get: { business.cashAppEnabled },
                    set: {
                        business.cashAppEnabled = $0
                        save()
                    }
                ))
                TextField("$handle or URL", text: Binding(
                    get: { business.cashAppHandleOrLink ?? "" },
                    set: {
                        business.cashAppHandleOrLink = normalizeCashAppInput($0)
                        save()
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func venmoCard(_ business: Business) -> some View {
        providerCard(
            logo: "venmo_logo",
            title: "Venmo",
            description: "Use a Venmo profile link and reconcile manual reports.",
            methodChips: ["Venmo"],
            feeNote: "Use your public Venmo profile link.",
            status: business.venmoEnabled ? "Enabled" : "Not connected",
            primaryTitle: "Enable Venmo",
            secondaryTitle: nil,
            primaryDisabled: false,
            secondaryDisabled: true
        ) {
            business.venmoEnabled = true
            business.venmoHandleOrLink = normalizeVenmoInput(business.venmoHandleOrLink ?? "")
            save()
        } onSecondaryTap: { }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Divider()
                Toggle("Enable Venmo", isOn: Binding(
                    get: { business.venmoEnabled },
                    set: {
                        business.venmoEnabled = $0
                        save()
                    }
                ))
                TextField("@handle or URL", text: Binding(
                    get: { business.venmoHandleOrLink ?? "" },
                    set: {
                        business.venmoHandleOrLink = normalizeVenmoInput($0)
                        save()
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func achCard(_ business: Business) -> some View {
        providerCard(
            logo: "ach_logo",
            title: "ACH",
            description: "Manual bank transfer with instructions and reconciliation.",
            methodChips: ["Bank Transfer"],
            feeNote: "Store only account/routing last 4 digits.",
            status: business.achEnabled ? "Enabled" : "Not connected",
            primaryTitle: "Enable ACH",
            secondaryTitle: "Edit Instructions",
            primaryDisabled: false,
            secondaryDisabled: false
        ) {
            business.achEnabled = true
            save()
        } onSecondaryTap: {
            showingACHSheet = true
        }
    }

    @ViewBuilder
    private func providerCard(
        logo: String,
        title: String,
        description: String,
        methodChips: [String],
        feeNote: String,
        status: String,
        primaryTitle: String,
        secondaryTitle: String?,
        primaryDisabled: Bool,
        secondaryDisabled: Bool,
        onPrimaryTap: @escaping () async -> Void,
        onSecondaryTap: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusPill(status)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(methodChips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Text(feeNote)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(primaryTitle) {
                    Task { await onPrimaryTap() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(primaryDisabled)

                if let secondaryTitle {
                    Button(secondaryTitle) {
                        Task { await onSecondaryTap() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(secondaryDisabled)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        )
    }

    private func statusPill(_ text: String) -> some View {
        let colors = SBWTheme.chip(forStatus: text.uppercased())
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
    }

    private var stripeState: (label: String, isConnected: Bool) {
        let accountId = stripeStatus?.stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if accountId.isEmpty { return ("Not connected", false) }
        if stripeStatus?.chargesEnabled == true && stripeStatus?.payoutsEnabled == true {
            return ("Active", true)
        }
        return ("Pending", true)
    }

    private func resolveBusiness() {
        guard let id = activeBiz.activeBusinessID else {
            business = businesses.first
            return
        }
        business = businesses.first(where: { $0.id == id }) ?? businesses.first
    }

    private func save() {
        try? modelContext.save()
    }

    private func startStripe() async {
        guard let business else { return }
        guard !isStartingStripe else { return }
        isStartingStripe = true
        defer { isStartingStripe = false }

        do {
            let returnURL = URL(string: "smallbizworkspace://settings/payments/stripe-return")!
            let url = try await PortalPaymentsAPI.shared.startStripeConnect(
                businessId: business.id,
                returnURL: returnURL
            )
            stripeURL = url
            showStripeSafari = true
        } catch {
            stripeError = error.localizedDescription
            showStripeError = true
        }
    }

    private func refreshStripeStatus() async {
        guard let business else { return }
        guard !isLoadingStripe else { return }
        isLoadingStripe = true
        defer { isLoadingStripe = false }
        do {
            let status = try await PortalPaymentsAPI.shared.fetchStripeConnectStatus(businessId: business.id)
            stripeStatus = status
            business.stripeAccountId = status.stripeAccountId
            business.stripeOnboardingStatus = status.onboardingStatus
            business.stripeChargesEnabled = status.chargesEnabled
            business.stripePayoutsEnabled = status.payoutsEnabled
            save()
        } catch {
            stripeError = error.localizedDescription
            showStripeError = true
        }
    }

    private func refreshPayPalPlatformStatus() async {
        guard !isLoadingPayPalPlatform else { return }
        isLoadingPayPalPlatform = true
        defer { isLoadingPayPalPlatform = false }
        do {
            let status = try await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            payPalPlatformEnabled = status.enabled
            business?.paypalEnabled = status.enabled
            save()
        } catch {
            payPalError = error.localizedDescription
            showPayPalError = true
        }
    }

    @ViewBuilder
    private func achEditorSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
                Toggle("Enable ACH", isOn: Binding(
                    get: { business.achEnabled },
                    set: {
                        business.achEnabled = $0
                        save()
                    }
                ))
                TextField("Recipient Name", text: Binding(
                    get: { business.achRecipientName ?? "" },
                    set: {
                        business.achRecipientName = emptyToNil($0)
                        save()
                    }
                ))
                TextField("Bank Name", text: Binding(
                    get: { business.achBankName ?? "" },
                    set: {
                        business.achBankName = emptyToNil($0)
                        save()
                    }
                ))
                TextField("Account Last 4", text: Binding(
                    get: { business.achAccountLast4 ?? "" },
                    set: {
                        business.achAccountLast4 = sanitizeLast4($0)
                        save()
                    }
                ))
                .keyboardType(.numberPad)
                TextField("Routing Last 4", text: Binding(
                    get: { business.achRoutingLast4 ?? "" },
                    set: {
                        business.achRoutingLast4 = sanitizeLast4($0)
                        save()
                    }
                ))
                .keyboardType(.numberPad)
                TextEditor(text: Binding(
                    get: { business.achInstructions ?? "" },
                    set: {
                        business.achInstructions = emptyToNil($0)
                        save()
                    }
                ))
                .frame(minHeight: 120)
            }
            .navigationTitle("ACH Instructions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingACHSheet = false }
                }
            }
        }
    }

    private func normalizeURL(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }

    private func normalizeCashAppInput(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        let handle = trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed
        return "https://cash.app/$\(handle)"
    }

    private func normalizeVenmoInput(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return "https://venmo.com/u/\(handle)"
    }

    private func sanitizeLast4(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        let value = String(digits.suffix(4))
        return value.isEmpty ? nil : value
    }

    private func emptyToNil(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
