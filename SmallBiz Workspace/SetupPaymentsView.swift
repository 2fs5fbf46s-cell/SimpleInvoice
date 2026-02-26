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
    @State private var stripeEnabled = true
    @State private var isTestingStripeBackend = false
    @State private var stripeBackendTestResult: String?

    @State private var isLoadingPayPalStatus = false
    @State private var payPalConnectStatus: PayPalConnectStatusResponse?
    @State private var isStartingPayPal = false
    @State private var payPalURL: URL?
    @State private var showPayPalSafari = false
    @State private var showPayPalHelpSheet = false
    @State private var payPalPartnerAvailable = false
    @State private var isTestingPayPalBackend = false
    @State private var payPalBackendTestResult: String?
    @State private var payPalLastCheckedAt: Date?
    @State private var payPalAlertMessage: String?
    @State private var payPalAlertDetails: String?
    @State private var showPayPalError = false

    @State private var showingACHSheet = false
    @State private var showingSquareSheet = false
    @State private var showingCashAppSheet = false
    @State private var showingVenmoSheet = false
    @State private var showingPayPalConfigSheet = false
#if DEBUG
    @State private var showDiagnostics = false
#endif

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

                    sectionLabel("Card Payments")
                    if let business {
                        stripeCard(business)
                        payPalCard(business)
                        squareCard(business)
                    } else {
                        loadingCard
                    }

                    sectionLabel("Peer-to-Peer")
                    if let business {
                        cashAppCard(business)
                        venmoCard(business)
                    } else {
                        loadingCard
                    }

                    sectionLabel("Bank")
                    if let business {
                        achCard(business)
                    } else {
                        loadingCard
                    }

                    #if DEBUG
                    diagnosticsSection
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Spacer().frame(height: 24)
        }
        .navigationTitle("Setup Payments")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            resolveBusiness()
            Task { await refreshStripeStatus() }
            Task { await refreshPayPalStatus() }
            Task { await refreshPayPalCapability() }
        }
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            resolveBusiness()
            Task { await refreshStripeStatus() }
            Task { await refreshPayPalStatus() }
            Task { await refreshPayPalCapability() }
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
                    Text("Setup PayPal (Admin)")
                        .font(.headline)
                    Text("PayPal platform payments are \(payPalPlatformReadyText).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !payPalPartnerAvailable {
                        Text("Partner onboarding is not enabled yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Partner onboarding is available. Use Connect to link your merchant account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Required:")
                        .font(.subheadline.weight(.semibold))
                    Text("• PAYPAL_PARTNER_CLIENT_ID\n• PAYPAL_PARTNER_CLIENT_SECRET\n• PAYPAL_PARTNER_RETURN_URL_BASE\n• PAYPAL_PARTNER_PRIVACY_URL\n• PAYPAL_PARTNER_USER_AGREEMENT_URL")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        .alert("PayPal status check failed", isPresented: $showPayPalError) {
            #if DEBUG
            Button("Copy Details") {
                UIPasteboard.general.string = payPalAlertDetails ?? ""
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(payPalAlertMessage ?? "PayPal status unavailable. Please verify backend deployment and environment variables.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose how customers can pay you. Enable only what you want to offer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    private func stripeCard(_ business: Business) -> some View {
        let status = stripeState
        return PaymentProviderCard(
            logoName: "stripe_logo",
            fallbackSymbol: "creditcard.fill",
            title: "Stripe Connect",
            subtitle: "Accept cards and wallet payments with connected payouts.",
            tags: ["Visa", "Mastercard", "Apple Pay"],
            statusText: status.label,
            statusStyle: status.style,
            enabledBinding: $stripeEnabled,
            hintWhenDisabled: "Enable to configure Stripe.",
            primaryAction: .init(
                title: stripePrimaryActionTitle,
                isLoading: isStartingStripe,
                isDisabled: isStartingStripe || isLoadingStripe,
                action: { Task { await openStripeOnboarding() } }
            )
        ) {
            if status.actionRequired {
                Text("Finish setup to enable payouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Refresh Status") {
                Task { await refreshStripeStatus() }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .disabled(isLoadingStripe || isStartingStripe)
        }
    }

    private func payPalCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "paypal_logo",
            fallbackSymbol: "p.circle.fill",
            title: "PayPal",
            subtitle: "Connect PayPal to route payments to your PayPal account.",
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
            hintWhenDisabled: "Enable to configure PayPal.",
            primaryAction: .init(
                title: payPalPrimaryActionTitle,
                isLoading: isStartingPayPal,
                isDisabled: isLoadingPayPalStatus || isStartingPayPal,
                action: { Task { await payPalPrimaryActionTapped() } }
            )
        ) {
            if let lastChecked = payPalLastCheckedAt {
                Text("Last checked: \(lastChecked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isLoadingPayPalStatus {
                Text(payPalHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Button("Refresh Status") {
                    Task { await refreshPayPalStatus() }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .disabled(isLoadingPayPalStatus || isStartingPayPal)

                Button("Configure") {
                    showingPayPalConfigSheet = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                if isLoadingPayPalStatus {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func squareCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "square_logo",
            fallbackSymbol: "squareshape",
            title: "Square",
            subtitle: "Share a Square payment link and reconcile reports.",
            tags: ["Cards", "Wallets"],
            statusText: business.squareEnabled ? "Active" : "Disabled",
            statusStyle: business.squareEnabled ? .active : .notConnected,
            enabledBinding: Binding(
                get: { business.squareEnabled },
                set: { newValue in
                    business.squareEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Enable to configure Square.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.squareEnabled,
                action: { showingSquareSheet = true }
            )
        ) {
            EmptyView()
        }
    }

    private func cashAppCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "cashapp_logo",
            fallbackSymbol: "dollarsign.circle.fill",
            title: "Cash App",
            subtitle: "Accept Cash App transfers with reconciliation.",
            tags: ["Cash App"],
            statusText: business.cashAppEnabled ? "Active" : "Disabled",
            statusStyle: business.cashAppEnabled ? .active : .notConnected,
            enabledBinding: Binding(
                get: { business.cashAppEnabled },
                set: { newValue in
                    business.cashAppEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Enable to configure Cash App.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.cashAppEnabled,
                action: { showingCashAppSheet = true }
            )
        ) {
            EmptyView()
        }
    }

    private func venmoCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "venmo_logo",
            fallbackSymbol: "v.circle.fill",
            title: "Venmo",
            subtitle: "Use a Venmo profile link and reconcile reports.",
            tags: ["Venmo"],
            statusText: business.venmoEnabled ? "Active" : "Disabled",
            statusStyle: business.venmoEnabled ? .active : .notConnected,
            enabledBinding: Binding(
                get: { business.venmoEnabled },
                set: { newValue in
                    business.venmoEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Enable to configure Venmo.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.venmoEnabled,
                action: { showingVenmoSheet = true }
            )
        ) {
            EmptyView()
        }
    }

    private func achCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "ach_logo",
            fallbackSymbol: "building.columns.fill",
            title: "ACH",
            subtitle: "Manual bank transfer with instructions and reconciliation.",
            tags: ["Bank Transfer"],
            statusText: business.achEnabled ? "Active" : "Disabled",
            statusStyle: business.achEnabled ? .active : .notConnected,
            enabledBinding: Binding(
                get: { business.achEnabled },
                set: { newValue in
                    business.achEnabled = newValue
                    save()
                }
            ),
            hintWhenDisabled: "Enable to configure ACH.",
            primaryAction: .init(
                title: "Configure",
                isLoading: false,
                isDisabled: !business.achEnabled,
                action: { showingACHSheet = true }
            )
        ) {
            EmptyView()
        }
    }

    private var stripeState: (label: String, style: ProviderStatusStyle, isConnected: Bool, isActive: Bool, actionRequired: Bool) {
        let accountId = stripeStatus?.stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if accountId.isEmpty { return ("Not connected", .notConnected, false, false, false) }

        let actionRequired = stripeStatus?.actionRequired ?? true
        let isActive = stripeStatus?.chargesEnabled == true &&
            stripeStatus?.payoutsEnabled == true &&
            !actionRequired

        if isActive {
            return ("Active", .active, true, true, false)
        }
        return ("Pending", .pending, true, false, true)
    }

    private var stripePrimaryActionTitle: String {
        let state = stripeState
        if !state.isConnected { return "Connect Stripe" }
        if state.isConnected && !state.isActive { return "Finish Setup" }
        return "Manage"
    }

    private var payPalStatusLabel: String {
        if isLoadingPayPalStatus { return "Checking" }
        let state = payPalState
        switch state {
        case .notConfigured:
            return "Not configured"
        case .notConnected:
            return "Not connected"
        case .pending:
            return "Pending"
        case .active:
            if let env = payPalConnectStatus?.env?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                if env == "sandbox" { return "Sandbox" }
                if env == "live" { return "Live" }
            }
            return "Available"
        case .error:
            return "Error"
        }
    }

    private var payPalStatusStyle: ProviderStatusStyle {
        if isLoadingPayPalStatus { return .pending }
        switch payPalState {
        case .active: return .active
        case .pending: return .pending
        case .notConfigured, .notConnected: return .notConnected
        case .error: return .error
        }
    }

    private var payPalHelperText: String {
        switch payPalState {
        case .active:
            let env = payPalConnectStatus?.env?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
            return "Environment: \(env)"
        case .notConfigured:
            return "Add PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET in backend."
        case .notConnected:
            return "Connect PayPal to route payments to your PayPal account."
        case .pending:
            return "Complete onboarding in PayPal, then refresh status."
        case .error:
            return sanitizePayPalMessage(payPalConnectStatus?.message)
        }
    }

    private var payPalPlatformReadyText: String {
        guard let status = payPalConnectStatus else { return "not configured" }
        return status.canCreateOrder ? "enabled" : "not configured"
    }

    private func sanitizePayPalMessage(_ message: String?) -> String {
        let trimmed = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "PayPal status unavailable. Please verify backend deployment and environment variables."
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

    private func save() {
        try? modelContext.save()
    }

    private func openStripeOnboarding() async {
        guard let business else { return }
        guard !isStartingStripe else { return }
        isStartingStripe = true
        defer { isStartingStripe = false }

        do {
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
            stripeURL = url
            showStripeSafari = true
        } catch {
            let details = errorDebugDetails(error)
            stripeAlertDetails = details
            stripeAlertMessage = stripeUserMessage(error: error, details: details)
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
            stripeEnabled = !((status.stripeAccountId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            save()
        } catch {
            let details = errorDebugDetails(error)
            stripeAlertDetails = details
            stripeAlertMessage = stripeUserMessage(error: error, details: details)
            showStripeError = true
        }
    }

    private func testStripeBackend() async {
        guard !isTestingStripeBackend else { return }
        isTestingStripeBackend = true
        defer { isTestingStripeBackend = false }
        let result = await PortalPaymentsAPI.shared.testAdminBackendAuth()
        stripeBackendTestResult = result.status
    }

    private func refreshPayPalStatus() async {
        guard let business else { return }
        guard !isLoadingPayPalStatus else { return }
        isLoadingPayPalStatus = true
        defer {
            isLoadingPayPalStatus = false
            payPalLastCheckedAt = Date()
        }

        do {
            let status = try await PortalPaymentsAPI.shared.paypalConnectStatus(businessId: business.id)
            payPalPartnerAvailable = true
            payPalConnectStatus = status
            let platform = try? await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            business.paypalEnabled = platform?.canCreateOrder ?? status.canCreateOrder
            business.paypalMerchantId = status.paypalMerchantId
            business.paypalOnboardingStatus = status.onboardingStatus
            business.paypalLinkedAtMs = status.paypalLinkedAtMs
            business.paypalLastCheckedAtMs = status.paypalLastCheckedAtMs
            business.paypalEnv = status.env ?? platform?.env
            save()
        } catch {
            let fallback = "PayPal status unavailable. Please verify backend deployment and environment variables."
            let message = (error as? PaymentServiceResponseError)?.message ?? fallback
            if case PortalBackendError.http(let code, _, _) = error, code == 404 || code == 405 {
                payPalPartnerAvailable = false
                let platform = try? await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                payPalConnectStatus = PayPalConnectStatusResponse(
                    ok: true,
                    configured: platform?.configured ?? false,
                    env: platform?.env,
                    canCreateOrder: platform?.canCreateOrder ?? false,
                    message: "Partner onboarding is not enabled yet.",
                    onboardingStatus: "not_connected",
                    paypalMerchantId: business.paypalMerchantId,
                    paypalLinkedAtMs: business.paypalLinkedAtMs,
                    paypalLastCheckedAtMs: nowMs
                )
                business.paypalEnabled = platform?.canCreateOrder ?? false
                business.paypalEnv = platform?.env
                business.paypalLastCheckedAtMs = nowMs
                save()
                return
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
            payPalAlertDetails = errorDebugDetails(error)
            payPalAlertMessage = fallback
            showPayPalError = true
        }
    }

    private func refreshPayPalCapability() async {
        guard let business else { return }
        payPalPartnerAvailable = await PortalPaymentsAPI.shared.isPayPalPartnerConnectAvailable(businessId: business.id)
    }

    private enum PayPalState {
        case notConfigured
        case notConnected
        case pending
        case active
        case error
    }

    private var payPalState: PayPalState {
        guard let status = payPalConnectStatus else {
            return .notConfigured
        }
        if !status.ok {
            return .error
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
        case .notConfigured: return "Setup PayPal (Admin)"
        case .notConnected: return "Connect PayPal"
        case .pending: return "Finish Setup"
        case .active: return "Manage"
        case .error: return "Connect PayPal"
        }
    }

    private func payPalPrimaryActionTapped() async {
        guard let business else { return }
        guard payPalPartnerAvailable else {
            showPayPalHelpSheet = true
            return
        }
        switch payPalState {
        case .notConfigured:
            showPayPalHelpSheet = true
        case .active:
            if let dashboardURL = payPalDashboardURL() {
                payPalURL = dashboardURL
                showPayPalSafari = true
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
                    payPalURL = url
                    showPayPalSafari = true
                } else {
                    payPalAlertMessage = start.message ?? "PayPal is connected."
                    payPalAlertDetails = start.message ?? "No onboarding URL returned."
                    showPayPalError = true
                }
            } catch {
                payPalAlertDetails = errorDebugDetails(error)
                payPalAlertMessage = (error as? PaymentServiceResponseError)?.message ??
                    "PayPal status unavailable. Please verify backend deployment and environment variables."
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

    private func testPayPalBackend() async {
        #if DEBUG
        guard !isTestingPayPalBackend else { return }
        isTestingPayPalBackend = true
        defer { isTestingPayPalBackend = false }
        let result = await PortalPaymentsAPI.shared.testPayPalBackendHealth()
        payPalBackendTestResult = result.status
        #endif
    }

    private func errorDebugDetails(_ error: Error) -> String {
        if let serviceError = error as? PaymentServiceResponseError {
            return serviceError.details
        }
        return (error as NSError).localizedDescription
    }

    private func stripeUserMessage(error: Error, details: String) -> String {
        if let serviceError = error as? PaymentServiceResponseError {
            return serviceError.message
        }
        return mapStripeErrorMessage(details)
    }

    private func mapStripeErrorMessage(_ details: String) -> String {
        let lower = details.lowercased()
        if lower.contains("http 405") || lower.contains("method not allowed") {
            return "Stripe setup service misconfigured (method not allowed)."
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
            return "Stripe Connect isn’t enabled for the platform account yet. Enable Connect in the Stripe dashboard (Live mode)."
        }
        return "Stripe service unavailable. Try again."
    }

    @ViewBuilder
    private func squareEditorSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Square")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingSquareSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func cashAppEditorSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Cash App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingCashAppSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func venmoEditorSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Venmo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingVenmoSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func achEditorSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
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

    @ViewBuilder
    private func payPalConfigSheet(for business: Business) -> some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("PayPal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingPayPalConfigSheet = false }
                }
            }
        }
    }

#if DEBUG
    private var diagnosticsSection: some View {
        DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        Task { await testStripeBackend() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingStripeBackend {
                                ProgressView().controlSize(.small)
                            }
                            Text("Test Stripe Backend")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingStripeBackend)

                    if let stripeBackendTestResult {
                        Text(stripeBackendTestResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await testPayPalBackend() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingPayPalBackend {
                                ProgressView().controlSize(.small)
                            }
                            Text("Test PayPal Backend")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingPayPalBackend)

                    if let payPalBackendTestResult {
                        Text(payPalBackendTestResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
#endif

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
    case active
    case enabled
    case pending
    case notConnected
    case error
    case info

    var background: Color {
        switch self {
        case .active: return Color.green.opacity(0.2)
        case .enabled: return Color.blue.opacity(0.2)
        case .pending: return Color.orange.opacity(0.2)
        case .notConnected: return Color.white.opacity(0.12)
        case .error: return Color.red.opacity(0.2)
        case .info: return Color.white.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .active: return .green
        case .enabled: return .blue
        case .pending: return .orange
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
                                .background(Color.white.opacity(0.12))
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
                    .tint(SBWTheme.brandBlue)
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
