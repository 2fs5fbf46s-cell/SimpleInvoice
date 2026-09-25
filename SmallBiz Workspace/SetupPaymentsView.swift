import SwiftUI
import SwiftData
import UIKit

struct SetupPaymentsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var businesses: [Business]

    @State private var business: Business?

    @State private var stripeStatus: StripeConnectStatus?
    @State private var isLoadingStripe = false
    @State private var isStartingStripe = false
    @State private var stripeAlertMessage: String?
    @State private var stripeAlertDetails: String?
    @State private var showStripeError = false
    @State private var stripeURL: URL?
    @State private var showStripeSafari = false
    @State private var awaitingStripeReturn = false
    /// What the payment methods looked like on arrival; leaving with a
    /// change republishes open invoices (PaymentMethodsPublisher).
    @State private var methodsOnAppear: String? = nil
    @State private var stripeStatusError = false

    @State private var isLoadingPayPalStatus = false
    @State private var payPalConnectStatus: PayPalConnectStatusResponse?
    @State private var isStartingPayPal = false
    @State private var payPalURL: URL?
    @State private var showPayPalSafari = false
    @State private var showPayPalHelpSheet = false
    @State private var payPalPartnerAvailable = false
    @State private var payPalLastCheckedAt: Date?
    @State private var payPalAlertMessage: String?
    @State private var payPalAlertDetails: String?
    @State private var showPayPalError = false

    /// Inline copies of the two status-read failures. These used to be modal
    /// alerts that fired on appear — four of them across two screens, none of
    /// them prompted by anything the user did.
    @State private var stripeStatusNotice: String? = nil
    @State private var payPalStatusNotice: String? = nil
    @State private var payPalStatusNote: String?

    @State private var showingACHSheet = false
    @State private var showingSquareSheet = false
    @State private var showingCashAppSheet = false
    @State private var showingVenmoSheet = false
    @State private var showingPayPalConfigSheet = false

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
                VStack(alignment: .leading, spacing: 18) {
                    header

                    sectionLabel("Online, Paid Right Away")
                    if let business {
                        stripeCard(business)
                        payPalCard(business)
                    } else {
                        loadingCard
                    }

                    sectionLabel("You Confirm When It Arrives")
                        .padding(.top, 8)
                    if let business {
                        venmoCard(business)
                        cashAppCard(business)
                        squareCard(business)
                        achCard(business)
                    } else {
                        loadingCard
                    }

                    #if DEBUG
                    NavigationLink {
                        SetupPaymentsDiagnosticsView(businessId: business?.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(.secondary)
                            Text("Diagnostics")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Spacer().frame(height: 24)
        }
        .navigationTitle("Payment Methods")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .onAppear {
            reloadForActiveBusiness()
            if methodsOnAppear == nil, let business { methodsOnAppear = Self.methodsSignature(business) }
        }
        .onDisappear {
            guard let business, let before = methodsOnAppear,
                  Self.methodsSignature(business) != before else { return }
            let businessID = business.id
            let context = modelContext
            Task { await PaymentMethodsPublisher.republishOpenInvoices(businessID: businessID, context: context) }
        }
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            reloadForActiveBusiness()
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
        .sheet(isPresented: $showingSquareSheet) {
            if let business {
                squareEditorSheet(for: business)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingCashAppSheet) {
            if let business {
                cashAppEditorSheet(for: business)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingVenmoSheet) {
            if let business {
                venmoEditorSheet(for: business)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingPayPalConfigSheet) {
            if let business {
                payPalConfigSheet(for: business)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showPayPalSafari) {
            if let payPalURL {
                SafariView(url: payPalURL) {
                    showPayPalSafari = false
                    Task { await refreshPayPalStatus() }
                }
            } else {
                Text("Unable to open PayPal onboarding.")
            }
        }
        .sheet(isPresented: $showPayPalHelpSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Taking PayPal payments")
                        .font(.headline)
                    if payPalPartnerAvailable {
                        Text("Connect your PayPal business account and customers can pay PayPal invoices straight from their portal link.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Tap Connect to sign in to PayPal. You'll come back here when it's done.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Direct PayPal checkout isn't available in the app yet — we're finishing the approval process with PayPal.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("In the meantime you can add a PayPal.me link and customers can pay you there. Your invoice will show it as a payment option.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .navigationTitle("PayPal Setup")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showPayPalHelpSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Stripe", isPresented: $showStripeError) {
            #if DEBUG
            Button("Copy Details") {
                UIPasteboard.general.string = stripeAlertDetails ?? ""
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(stripeAlertMessage ?? "Stripe service unavailable. Try again.")
        }
        .alert("PayPal", isPresented: $showPayPalError) {
            #if DEBUG
            Button("Copy Details") {
                UIPasteboard.general.string = payPalAlertDetails ?? ""
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(payPalAlertMessage ?? "Couldn't check PayPal just now. Try again in a minute.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What clients can use to pay your invoices. Turn one off to stop offering it; nothing is disconnected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let notice = stripeStatusNotice {
                statusNotice(notice)
            }
            if let notice = payPalStatusNotice {
                statusNotice(notice)
            }
        }
    }

    /// What a failed status read looks like now: a row you can read past, with a
    /// way to try again, instead of a dialog you have to dismiss.
    private func statusNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(SBWTheme.attention)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Retry") { reloadForActiveBusiness() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(SBWTheme.brand)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SBWTheme.attention.opacity(0.12))
        )
    }

    private var loadingCard: some View {
        PaymentProviderCard(
            logoName: nil,
            fallbackSymbol: "creditcard",
            title: "Loading",
            subtitle: "Fetching payment settings",
            statusText: "Loading",
            statusStyle: .info
        ) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading payment providers…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func inlineHelperRow(
        text: String,
        isBusy: Bool = false,
        actionTitle: String = "Refresh",
        actionDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SBWTheme.brand.opacity(0.85))
                .disabled(actionDisabled)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func stripeCard(_ business: Business) -> some View {
        let status = stripeState
        return PaymentProviderCard(
            logoName: "stripe_logo",
            fallbackSymbol: "creditcard.fill",
            title: "Card (Stripe)",
            subtitle: "Clients pay by card or Apple Pay. Money goes to your bank.",
            tags: ["Visa", "Mastercard", "Apple Pay"],
            statusText: status.label,
            statusStyle: status.style,
            enabledBinding: Binding(
                get: { stripeEnabled },
                set: { value in
                    handleStripeToggle(value, business: business)
                }
            ),
            hintWhenDisabled: "Turn on to offer card payments.",
            primaryAction: nil
        ) {
            inlineHelperRow(
                text: stripeHelperText,
                isBusy: isLoadingStripe,
                actionTitle: "Refresh",
                actionDisabled: isLoadingStripe || isStartingStripe
            ) {
                Task { await refreshStripeStatus() }
            }
            HStack(spacing: 12) {
                Button {
                    Task { await openStripeOnboarding() }
                } label: {
                    HStack(spacing: 8) {
                        if isStartingStripe {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(stripePrimaryActionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brand)
                .disabled(isStartingStripe || isLoadingStripe)
            }
        }
    }

    private func payPalCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "paypal_logo",
            fallbackSymbol: "p.circle.fill",
            title: "PayPal",
            subtitle: "Clients pay with PayPal. Money goes to your PayPal account.",
            tags: ["PayPal", "Cards"],
            statusText: payPalStatusLabel,
            statusStyle: payPalStatusStyle,
            enabledBinding: Binding(
                get: { business.paypalEnabled },
                set: {
                    business.paypalEnabled = $0
                    save()
                }
            ),
            hintWhenDisabled: "Turn on to offer PayPal.",
            primaryAction: nil
        ) {
            if let note = payPalStatusNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastChecked = payPalLastCheckedAt {
                Text("Last checked: \(lastChecked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            inlineHelperRow(
                text: payPalHelperText,
                isBusy: isLoadingPayPalStatus,
                actionTitle: "Refresh",
                actionDisabled: isLoadingPayPalStatus || isStartingPayPal
            ) {
                Task { await refreshPayPalStatus() }
            }
            HStack(spacing: 12) {
                Button {
                    Task { await payPalPrimaryActionTapped() }
                } label: {
                    HStack(spacing: 8) {
                        if isStartingPayPal {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(payPalPrimaryActionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brand)
                .disabled(isLoadingPayPalStatus || isStartingPayPal)
            }
        }
    }

    private func squareCard(_ business: Business) -> some View {
        let configured = isSquareConfigured(for: business)
        let statusText = manualStatusText(isEnabled: business.squareEnabled, isConfigured: configured)
        let statusStyle = manualStatusStyle(isEnabled: business.squareEnabled, isConfigured: configured)
        return PaymentProviderCard(
            logoName: "square_logo",
            fallbackSymbol: "squareshape",
            title: "Square",
            subtitle: "Clients pay through your Square link. You mark the invoice paid.",
            tags: ["Cards", "Wallets"],
            statusText: statusText,
            statusStyle: statusStyle,
            enabledBinding: Binding(
                get: { business.squareEnabled },
                set: { newValue in
                    business.squareEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Turn on to offer Square.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.squareEnabled,
                action: { showingSquareSheet = true }
            )
        ) {
            Text(squareSummaryText(for: business, configured: configured))
                .font(.caption)
                .foregroundColor(configured ? .secondary : SBWTheme.attention)
        }
    }

    private func cashAppCard(_ business: Business) -> some View {
        let configured = isCashAppConfigured(for: business)
        let statusText = manualStatusText(isEnabled: business.cashAppEnabled, isConfigured: configured)
        let statusStyle = manualStatusStyle(isEnabled: business.cashAppEnabled, isConfigured: configured)
        return PaymentProviderCard(
            logoName: "cashapp_logo",
            fallbackSymbol: "dollarsign.circle.fill",
            title: "Cash App",
            subtitle: "Clients send to your $cashtag. You mark the invoice paid.",
            tags: ["Cash App"],
            statusText: statusText,
            statusStyle: statusStyle,
            enabledBinding: Binding(
                get: { business.cashAppEnabled },
                set: { newValue in
                    business.cashAppEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Turn on to offer Cash App.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.cashAppEnabled,
                action: { showingCashAppSheet = true }
            )
        ) {
            Text(cashAppSummaryText(for: business, configured: configured))
                .font(.caption)
                .foregroundColor(configured ? .secondary : SBWTheme.attention)
        }
    }

    private func venmoCard(_ business: Business) -> some View {
        let configured = isVenmoConfigured(for: business)
        let statusText = manualStatusText(isEnabled: business.venmoEnabled, isConfigured: configured)
        let statusStyle = manualStatusStyle(isEnabled: business.venmoEnabled, isConfigured: configured)
        return PaymentProviderCard(
            logoName: "venmo_logo",
            fallbackSymbol: "v.circle.fill",
            title: "Venmo",
            subtitle: "Clients send to your Venmo. You mark the invoice paid.",
            tags: ["Venmo"],
            statusText: statusText,
            statusStyle: statusStyle,
            enabledBinding: Binding(
                get: { business.venmoEnabled },
                set: { newValue in
                    business.venmoEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Turn on to offer Venmo.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.venmoEnabled,
                action: { showingVenmoSheet = true }
            )
        ) {
            Text(venmoSummaryText(for: business, configured: configured))
                .font(.caption)
                .foregroundColor(configured ? .secondary : SBWTheme.attention)
        }
    }

    private func achCard(_ business: Business) -> some View {
        let configured = isACHConfigured(for: business)
        let statusText = manualStatusText(isEnabled: business.achEnabled, isConfigured: configured)
        let statusStyle = manualStatusStyle(isEnabled: business.achEnabled, isConfigured: configured)
        return PaymentProviderCard(
            logoName: "ach_logo",
            fallbackSymbol: "building.columns.fill",
            title: "Bank Transfer",
            subtitle: "Clients transfer using your instructions. You mark the invoice paid.",
            tags: ["Bank Transfer"],
            statusText: statusText,
            statusStyle: statusStyle,
            enabledBinding: Binding(
                get: { business.achEnabled },
                set: { newValue in
                    business.achEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Turn on to offer bank transfer.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.achEnabled,
                action: { showingACHSheet = true }
            )
        ) {
            Text(achSummaryText(for: business, configured: configured))
                .font(.caption)
                .foregroundColor(configured ? .secondary : SBWTheme.attention)
        }
    }

    private var stripeState: (label: String, style: ProviderStatusStyle, isConnected: Bool, isActive: Bool, actionRequired: Bool) {
        guard stripeEnabled else { return ("Off", .disabled, false, false, false) }

        let accountId = normalizedStripeAccountId
        guard !accountId.isEmpty else { return ("Not connected", .pending, false, false, true) }

        if stripeStatusError {
            return ("Error", .error, true, false, true)
        }

        let actionRequired = stripeStatus?.actionRequired ?? true
        let detailsSubmitted = stripeStatus?.detailsSubmitted ?? false
        let chargesEnabled = stripeStatus?.chargesEnabled ?? business?.stripeChargesEnabled ?? false
        let payoutsEnabled = stripeStatus?.payoutsEnabled ?? business?.stripePayoutsEnabled ?? false
        let isActive = chargesEnabled && payoutsEnabled && !actionRequired && detailsSubmitted

        if isActive {
            return ("Connected", .active, true, true, false)
        }
        return ("Pending", .pending, true, false, true)
    }

    private var stripePrimaryActionTitle: String {
        let state = stripeState
        if !stripeEnabled { return "Connect Stripe" }
        if !state.isConnected { return "Connect Stripe" }
        if state.isConnected && !state.isActive { return "Finish Setup" }
        return "Manage"
    }

    private var stripeHelperText: String {
        let state = stripeState
        if !stripeEnabled {
            return "Enable Stripe to accept card payments."
        }
        if !state.isConnected {
            return "Connect Stripe to start accepting payments."
        }
        if state.isActive {
            return "Stripe is connected and payouts are enabled."
        }
        return "Finish setup to enable payouts."
    }

    private var payPalStatusLabel: String {
        guard business?.paypalEnabled == true else { return "Off" }
        if isLoadingPayPalStatus { return payPalState == .active ? "Connected" : "Checking…" }
        let state = payPalState
        switch state {
        case .unavailable:
            return "Not available yet"
        case .notConfigured, .notConnected:
            return "Not connected"
        case .pending:
            return "Finishing setup"
        case .active:
            return "Connected"
        case .error:
            return "Couldn't check"
        case .disabled:
            return "Off"
        }
    }

    private var payPalStatusStyle: ProviderStatusStyle {
        guard business?.paypalEnabled == true else { return .disabled }
        if isLoadingPayPalStatus { return .pending }
        switch payPalState {
        case .active: return .active
        case .pending: return .pending
        case .notConnected: return .pending
        case .unavailable: return .notConnected
        case .notConfigured: return .notConnected
        case .error: return .error
        case .disabled: return .disabled
        }
    }

    private var payPalHelperText: String {
        guard business?.paypalEnabled == true else {
            return "Enable PayPal to offer checkout with PayPal."
        }
        switch payPalState {
        case .unavailable:
            return "Direct PayPal checkout isn't available yet. Add a PayPal.me link and customers can still pay you with PayPal."
        case .active:
            let env = payPalConnectStatus?.env?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            // "sandbox" is a test account and worth saying plainly; live needs no label.
            return env == "sandbox"
                ? "Connected to a PayPal test account — payments won't be real."
                : "Connected. Customers can pay with PayPal."
        case .notConfigured:
            if payPalPartnerAvailable {
                return "Tap Connect to link your PayPal business account."
            }
            return "Direct PayPal checkout isn't available yet. A PayPal.me link works in the meantime."
        case .notConnected:
            return "Finish setup to link your PayPal merchant account."
        case .pending:
            return "Complete onboarding in PayPal, then refresh status."
        case .error:
            return sanitizePayPalMessage(payPalConnectStatus?.message)
        case .disabled:
            return "Enable PayPal to offer checkout with PayPal."
        }
    }

    private var payPalPlatformReadyText: String {
        guard let status = payPalConnectStatus else { return "not configured" }
        return status.canCreateOrder ? "enabled" : "not configured"
    }

    private func manualStatusText(isEnabled: Bool, isConfigured: Bool) -> String {
        if !isEnabled { return "Off" }
        return isConfigured ? "On" : "Add details"
    }

    private func manualStatusStyle(isEnabled: Bool, isConfigured: Bool) -> ProviderStatusStyle {
        if !isEnabled { return .disabled }
        return isConfigured ? .active : .pending
    }

    private func isSquareConfigured(for business: Business) -> Bool {
        normalizeURL(business.squareLink) != nil
    }

    private func isCashAppConfigured(for business: Business) -> Bool {
        normalizeCashAppInput(business.cashAppHandleOrLink ?? "") != nil
    }

    private func isVenmoConfigured(for business: Business) -> Bool {
        normalizeVenmoInput(business.venmoHandleOrLink ?? "") != nil
    }

    private func isACHConfigured(for business: Business) -> Bool {
        !(business.achInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func squareSummaryText(for business: Business, configured: Bool) -> String {
        guard business.squareEnabled else { return "Enable to configure." }
        if configured, let link = normalizeURL(business.squareLink) {
            return "Configured: \(link)"
        }
        return "Needs setup: add your Square payment link."
    }

    private func cashAppSummaryText(for business: Business, configured: Bool) -> String {
        guard business.cashAppEnabled else { return "Enable to configure." }
        if configured, let value = normalizeCashAppInput(business.cashAppHandleOrLink ?? "") {
            return "Configured: \(value)"
        }
        return "Needs setup: add your Cash App handle or link."
    }

    private func venmoSummaryText(for business: Business, configured: Bool) -> String {
        guard business.venmoEnabled else { return "Enable to configure." }
        if configured, let value = normalizeVenmoInput(business.venmoHandleOrLink ?? "") {
            return "Configured: \(value)"
        }
        return "Needs setup: add your Venmo handle or link."
    }

    private func achSummaryText(for business: Business, configured: Bool) -> String {
        guard business.achEnabled else { return "Enable to configure." }
        if configured {
            if let last4 = business.achAccountLast4, !last4.isEmpty {
                return "Configured: instructions saved (Acct ••••\(last4))"
            }
            return "Configured: bank transfer instructions saved."
        }
        return "Needs setup: add bank transfer instructions."
    }

    private func sanitizePayPalMessage(_ message: String?) -> String {
        let trimmed = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Couldn't check PayPal just now. Try again in a minute."
        }
        let noNewlines = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(noNewlines.prefix(140))
    }

    private func resolveBusiness() {
        guard let id = activeBiz.activeBusinessID else {
            business = businesses.first
            return
        }
        business = businesses.first(where: { $0.id == id }) ?? businesses.first
    }

    private var normalizedStripeAccountId: String {
        if let accountFromStatus = stripeStatus?.stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountFromStatus.isEmpty {
            return accountFromStatus
        }
        return business?.stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resetTransientStateForActiveBusiness() {
        stripeStatus = nil
        stripeStatusError = false
        stripeAlertMessage = nil
        stripeAlertDetails = nil
        showStripeError = false
        stripeStatusNotice = nil
        payPalStatusNotice = nil
        stripeURL = nil
        showStripeSafari = false
        awaitingStripeReturn = false

        payPalConnectStatus = nil
        payPalPartnerAvailable = false
        payPalLastCheckedAt = nil
        payPalStatusNote = nil
        payPalAlertMessage = nil
        payPalAlertDetails = nil
        showPayPalError = false
        payPalURL = nil
        showPayPalSafari = false

    }

    private func reloadForActiveBusiness() {
        resolveBusiness()
        resetTransientStateForActiveBusiness()
        Task {
            await refreshStripeStatus()
            await refreshPayPalCapability()
            await refreshPayPalStatus()
        }
    }

    private func save() {
        try? modelContext.save()
    }

    /// Everything a published invoice's payment options depend on.
    static func methodsSignature(_ b: Business) -> String {
        [
            "\(b.cardPaymentsOffered)", "\(b.paypalEnabled)", b.paypalMeFallback ?? b.paypalMeUrl ?? "",
            "\(b.squareEnabled)", b.squareLink ?? "", "\(b.cashAppEnabled)", b.cashAppHandleOrLink ?? "",
            "\(b.venmoEnabled)", b.venmoHandleOrLink ?? "", "\(b.achEnabled)", b.achInstructions ?? "",
            b.achAccountLast4 ?? "",
        ].joined(separator: "|")
    }

    private func openStripeOnboarding() async {
        guard let business else { return }
        guard !isStartingStripe else { return }
        isStartingStripe = true
        defer { isStartingStripe = false }

        do {
            stripeStatusError = false
            let returnURL = URL(string: "smallbizworkspace://settings/payments/stripe-return")!
            let state = stripeState
            let url: URL
            if state.isConnected {
                url = try await PortalPaymentsAPI.shared.resumeStripeConnect(
                    businessId: business.id,
                    returnURL: returnURL
                )
            } else {
                url = try await PortalPaymentsAPI.shared.startStripeConnect(
                    businessId: business.id,
                    returnURL: returnURL
                )
            }
            openStripeURL(url)
        } catch {
            let details = errorDebugDetails(error)
            stripeAlertDetails = details
            stripeAlertMessage = stripeUserMessage(error: error, details: details)
            stripeStatusError = true
            showStripeError = true
        }
    }

    /// On when card payments are offered: connected (or connecting) and not
    /// switched off. This used to be screen-only state that reset itself and
    /// did nothing when turned off.
    private var stripeEnabled: Bool {
        !normalizedStripeAccountId.isEmpty && (business?.stripeOffered ?? true)
    }

    private func handleStripeToggle(_ enabled: Bool, business: Business) {
        business.stripeOffered = enabled
        save()
        guard enabled else { return }
        let accountId = normalizedStripeAccountId
        if accountId.isEmpty {
            Task { await openStripeOnboarding() }
            return
        }
        if stripeState.actionRequired {
            Task { await openStripeOnboarding() }
        }
    }

    private func refreshStripeStatus() async {
        guard let business else { return }
        guard !isLoadingStripe else { return }
        let businessID = business.id
        isLoadingStripe = true
        defer { isLoadingStripe = false }

        do {
            let status = try await PortalPaymentsAPI.shared.fetchStripeConnectStatus(businessId: business.id)
            guard self.business?.id == businessID else { return }
            stripeStatus = status
            stripeStatusError = false
            business.stripeAccountId = status.stripeAccountId
            business.stripeOnboardingStatus = status.onboardingStatus
            business.stripeChargesEnabled = status.chargesEnabled
            business.stripePayoutsEnabled = status.payoutsEnabled
            save()
        } catch {
            guard self.business?.id == businessID else { return }
            // A status read the user didn't ask for must not block the screen.
            // It reports inline instead; see `statusNotice`.
            stripeStatusError = true
            stripeStatusNotice = stripeUserMessage(error: error, details: errorDebugDetails(error))
            SBWLog.payments.problem("Stripe status refresh failed: \(errorDebugDetails(error))")
        }
    }

    private func refreshPayPalStatus() async {
        guard let business else { return }
        guard !isLoadingPayPalStatus else { return }
        let businessID = business.id
        isLoadingPayPalStatus = true
        defer {
            isLoadingPayPalStatus = false
        }

        do {
            let status = try await PortalPaymentsAPI.shared.paypalConnectStatus(businessId: business.id)
            guard self.business?.id == businessID else { return }
            payPalPartnerAvailable = true
            payPalConnectStatus = status
            payPalStatusNote = nil
            let platform = try? await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            business.paypalMerchantId = status.paypalMerchantId
            business.paypalOnboardingStatus = status.onboardingStatus
            business.paypalLinkedAtMs = status.paypalLinkedAtMs
            business.paypalLastCheckedAtMs = status.paypalLastCheckedAtMs
            business.paypalEnv = status.env ?? platform?.env
            save()
            payPalLastCheckedAt = Date()
        } catch {
            guard self.business?.id == businessID else { return }
            let fallback = "Couldn't check PayPal just now. Try again in a minute."
            let message = payPalUserMessage(error: error, fallback: fallback)
            if case PortalBackendError.http(let code, _, _) = error, code == 404 || code == 405 {
                payPalPartnerAvailable = false
                let platform = try? await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                payPalConnectStatus = PayPalConnectStatusResponse(
                    ok: true,
                    configured: platform?.configured ?? false,
                    env: platform?.env,
                    canCreateOrder: platform?.canCreateOrder ?? false,
                    message: "Direct PayPal checkout isn't available yet.",
                    onboardingStatus: "not_connected",
                    paypalMerchantId: business.paypalMerchantId,
                    paypalLinkedAtMs: business.paypalLinkedAtMs,
                    paypalLastCheckedAtMs: nowMs
                )
                business.paypalEnv = platform?.env
                business.paypalLastCheckedAtMs = nowMs
                payPalStatusNote = "Direct PayPal checkout isn't available yet. You can add a PayPal.me link instead."
                payPalLastCheckedAt = Date()
                save()
                return
            }
            if case PortalBackendError.http(let code, _, _) = error, code == 401 || code == 403 {
                payPalStatusNote = PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .payPal)
            } else {
                payPalStatusNote = nil
            }
            payPalConnectStatus = PayPalConnectStatusResponse(
                ok: false,
                configured: false,
                env: nil,
                canCreateOrder: false,
                message: message,
                onboardingStatus: "error",
                paypalMerchantId: nil,
                paypalLinkedAtMs: nil,
                paypalLastCheckedAtMs: nil
            )
            // Inline, not modal: nobody asked for this read. See `statusNotice`.
            payPalStatusNotice = PaymentErrorPresenter.message(forServerText: message, provider: .payPal)
            SBWLog.payments.problem("PayPal status refresh failed: \(errorDebugDetails(error))")
            payPalLastCheckedAt = Date()
        }
    }

    private func refreshPayPalCapability() async {
        guard let business else { return }
        let businessID = business.id
        let available = await PortalPaymentsAPI.shared.isPayPalPartnerConnectAvailable(businessId: business.id)
        guard self.business?.id == businessID else { return }
        payPalPartnerAvailable = available
    }

    private enum PayPalState {
        case disabled
        case unavailable
        case notConfigured
        case notConnected
        case pending
        case active
        case error
    }

    private var payPalState: PayPalState {
        guard business?.paypalEnabled == true else {
            return .disabled
        }
        guard let status = payPalConnectStatus else {
            return payPalPartnerAvailable ? .notConfigured : .unavailable
        }
        if !status.ok {
            return .error
        }
        if !payPalPartnerAvailable {
            return .unavailable
        }
        if !status.configured {
            return .notConfigured
        }
        let onboarding = status.onboardingStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if onboarding == "active" {
            return status.canCreateOrder ? .active : .error
        }
        if onboarding == "pending" {
            return .pending
        }
        if onboarding == "error" {
            return .error
        }
        return .notConnected
    }

    private var payPalPrimaryActionTitle: String {
        if !payPalPartnerAvailable { return "Configure" }
        switch payPalState {
        case .disabled: return "Enable PayPal"
        case .unavailable: return "Configure"
        case .notConfigured: return "Set up PayPal"
        case .notConnected: return "Connect PayPal"
        case .pending: return "Finish Setup"
        case .active: return "Manage"
        case .error: return "Connect PayPal"
        }
    }

    private func payPalPrimaryActionTapped() async {
        guard let business else { return }
        guard business.paypalEnabled else { return }
        guard payPalPartnerAvailable else {
            showingPayPalConfigSheet = true
            return
        }
        switch payPalState {
        case .disabled:
            return
        case .unavailable:
            showingPayPalConfigSheet = true
        case .notConfigured:
            showPayPalHelpSheet = true
        case .active:
            if let dashboardURL = payPalDashboardURL() {
                openPayPalURL(dashboardURL)
            } else {
                payPalAlertMessage = "PayPal is connected."
                payPalAlertDetails = "Connected"
                showPayPalError = true
            }
        case .notConnected, .pending, .error:
            guard !isStartingPayPal else { return }
            isStartingPayPal = true
            defer { isStartingPayPal = false }
            do {
                let returnURL = URL(string: "https://portal.smallbizworkspace.com/portal/admin/paypal/connected")!
                let start = try await PortalPaymentsAPI.shared.paypalConnectStart(
                    businessId: business.id,
                    returnURL: returnURL
                )
                if !start.configured {
                    showPayPalHelpSheet = true
                    await refreshPayPalStatus()
                    return
                }
                if let url = start.url {
                    openPayPalURL(url)
                } else {
                    payPalAlertMessage = start.message ?? "PayPal is connected."
                    payPalAlertDetails = start.message ?? "No onboarding URL returned."
                    showPayPalError = true
                }
            } catch {
                payPalAlertDetails = errorDebugDetails(error)
                payPalAlertMessage = (error as? PaymentServiceResponseError)?.message ??
                    "Couldn't check PayPal just now. Try again in a minute."
                showPayPalError = true
            }
        }
    }

    private func payPalDashboardURL() -> URL? {
        let env = payPalConnectStatus?.env?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if env == "sandbox" {
            return URL(string: "https://www.sandbox.paypal.com")
        }
        return URL(string: "https://www.paypal.com/myaccount/summary")
    }

    private func openStripeURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else {
            stripeAlertMessage = "Couldn't open the setup page. Try again in a minute."
            stripeAlertDetails = "Invalid URL: \(url.absoluteString)"
            showStripeError = true
            return
        }
        stripeURL = url
        showStripeSafari = true
    }

    private func openPayPalURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else {
            payPalAlertMessage = "Couldn't open the setup page. Try again in a minute."
            payPalAlertDetails = "Invalid URL: \(url.absoluteString)"
            showPayPalError = true
            return
        }
        payPalURL = url
        showPayPalSafari = true
    }

    private func errorDebugDetails(_ error: Error) -> String {
        if let serviceError = error as? PaymentServiceResponseError {
            return serviceError.details
        }
        return (error as NSError).localizedDescription
    }

    private func stripeUserMessage(error: Error, details: String) -> String {
        // These used to read "This device needs to sign in again. Close and reopen the app, then try again." — a
        // note to a developer, shown to a business owner.
        if case PortalBackendError.missingAdminKey = error {
            return PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .stripe)
        }
        if case PortalBackendError.http(let code, _, _) = error, code == 401 || code == 403 {
            return PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .stripe)
        }
        if case PortalBackendError.badURL = error {
            return PaymentErrorPresenter.generic(.stripe)
        }
        if let serviceError = error as? PaymentServiceResponseError {
            // errorDescription, not message: `message` is the server's raw field
            // and is frequently a machine code.
            return serviceError.errorDescription ?? PaymentErrorPresenter.generic(.stripe)
        }
        return mapStripeErrorMessage(details)
    }

    private func mapStripeErrorMessage(_ details: String) -> String {
        let lower = details.lowercased()
        if lower.contains("http 405") || lower.contains("method not allowed") {
            return "Stripe setup service misconfigured (method not allowed)."
        }
        if lower.contains("http 401") || lower.contains("unauthorized") {
            return "This device needs to sign in again. Close and reopen the app, then try again."
        }
        if lower.contains("invalid portal backend url") || lower.contains("badurl") || lower.contains("invalid url") {
            return "Couldn't open the setup page. Try again in a minute."
        }
        if lower.contains("<!doctype html") ||
            lower.contains("<html") ||
            lower.contains("portal backend http 404") ||
            lower.contains("not found") {
            return "Stripe service unavailable. Try again."
        }
        if lower.contains("signed up for connect") ||
            lower.contains("connect is not enabled") ||
            lower.contains("platform_account_not_allowed") ||
            lower.contains("create new accounts") {
            return "Card payments aren't available yet. We're finishing setup with Stripe; try again later."
        }
        return "Stripe service unavailable. Try again."
    }

    private func payPalUserMessage(error: Error, fallback: String) -> String {
        if case PortalBackendError.missingAdminKey = error {
            return "This device needs to sign in again. Close and reopen the app, then try again."
        }
        if case PortalBackendError.badURL = error {
            return "Couldn't open the setup page. Try again in a minute."
        }
        if case PortalBackendError.http(let code, _, _) = error, code == 401 {
            return "This device needs to sign in again. Close and reopen the app, then try again."
        }
        if let serviceError = error as? PaymentServiceResponseError {
            return serviceError.message
        }
        return fallback
    }

    @ViewBuilder
    private func squareEditorSheet(for business: Business) -> some View {
        SquareConfigSheet(
            initialLink: business.squareLink ?? "",
            onSave: { normalized in
                business.squareLink = normalized
                save()
                showingSquareSheet = false
            },
            onCancel: { showingSquareSheet = false }
        )
    }

    @ViewBuilder
    private func cashAppEditorSheet(for business: Business) -> some View {
        CashAppConfigSheet(
            initialValue: business.cashAppHandleOrLink ?? "",
            onSave: { normalized in
                business.cashAppHandleOrLink = normalized
                save()
                showingCashAppSheet = false
            },
            onCancel: { showingCashAppSheet = false }
        )
    }

    @ViewBuilder
    private func venmoEditorSheet(for business: Business) -> some View {
        VenmoConfigSheet(
            initialValue: business.venmoHandleOrLink ?? "",
            onSave: { normalized in
                business.venmoHandleOrLink = normalized
                save()
                showingVenmoSheet = false
            },
            onCancel: { showingVenmoSheet = false }
        )
    }

    @ViewBuilder
    private func achEditorSheet(for business: Business) -> some View {
        ACHConfigSheet(
            initialInstructions: business.achInstructions ?? "",
            initialLast4: business.achAccountLast4 ?? "",
            onSave: { instructions, last4 in
                business.achInstructions = emptyToNil(instructions)
                business.achAccountLast4 = sanitizeLast4(last4)
                save()
                showingACHSheet = false
            },
            onCancel: { showingACHSheet = false }
        )
    }

    @ViewBuilder
    private func payPalConfigSheet(for business: Business) -> some View {
        PayPalFallbackConfigSheet(
            initialValue: business.paypalMeFallback ?? "",
            onSave: { normalized in
                business.paypalMeFallback = normalized
                business.paypalMeUrl = normalized
                save()
                showingPayPalConfigSheet = false
            },
            onCancel: { showingPayPalConfigSheet = false }
        )
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

private enum ProviderStatusStyle {
    case disabled
    case active
    case enabled
    case pending
    case notConnected
    case error
    case info

    var background: Color {
        switch self {
        case .disabled: return Color.primary.opacity(0.1)
        case .active: return SBWTheme.success.opacity(0.2)
        case .enabled: return SBWTheme.brandTint
        case .pending: return SBWTheme.attention.opacity(0.2)
        case .notConnected: return Color.primary.opacity(0.12)
        case .error: return Color.red.opacity(0.2)
        case .info: return Color.primary.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .disabled: return .secondary
        case .active: return SBWTheme.success
        case .enabled: return .blue
        case .pending: return SBWTheme.attention
        case .notConnected: return .secondary
        case .error: return .red
        case .info: return .secondary
        }
    }
}

private struct ProviderAction {
    let title: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void
}

private struct PaymentProviderCard<Content: View>: View {
    let logoName: String?
    let fallbackSymbol: String
    let title: String
    let subtitle: String
    let tags: [String]
    let statusText: String
    let statusStyle: ProviderStatusStyle
    let enabledBinding: Binding<Bool>?
    let hintWhenDisabled: String?
    let primaryAction: ProviderAction?
    @ViewBuilder let content: Content

    init(
        logoName: String?,
        fallbackSymbol: String,
        title: String,
        subtitle: String,
        tags: [String] = [],
        statusText: String,
        statusStyle: ProviderStatusStyle,
        enabledBinding: Binding<Bool>? = nil,
        hintWhenDisabled: String? = nil,
        primaryAction: ProviderAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.logoName = logoName
        self.fallbackSymbol = fallbackSymbol
        self.title = title
        self.subtitle = subtitle
        self.tags = tags
        self.statusText = statusText
        self.statusStyle = statusStyle
        self.enabledBinding = enabledBinding
        self.hintWhenDisabled = hintWhenDisabled
        self.primaryAction = primaryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let logoName {
                        Image(logoName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: fallbackSymbol)
                            .resizable()
                            .scaledToFit()
                            .padding(7)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusStyle.background))
                    .foregroundStyle(statusStyle.foreground)
                    .lineLimit(1)

                if let enabledBinding {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            let showDetailContent = enabledBinding?.wrappedValue ?? true
            if showDetailContent {
                content

                if let primaryAction {
                    Button {
                        primaryAction.action()
                    } label: {
                        HStack(spacing: 8) {
                            if primaryAction.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(primaryAction.title)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SBWTheme.brand)
                    .disabled(primaryAction.isDisabled)
                }
            } else if let hintWhenDisabled, !hintWhenDisabled.isEmpty {
                Text(hintWhenDisabled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        )
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// No inputs: queries and state drive every update.
extension SetupPaymentsView: Equatable {
    static func == (_: SetupPaymentsView, _: SetupPaymentsView) -> Bool {
        true
    }
}
