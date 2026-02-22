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

    @State private var isLoadingPayPalStatus = false
    @State private var payPalPlatformEnabled = false
    @State private var payPalEnv: String?
    @State private var payPalStatusError = false
    @State private var payPalLastCheckedAt: Date?
    @State private var payPalAlertMessage: String?
    @State private var payPalAlertDetails: String?
    @State private var showPayPalError = false

    @State private var manualExpanded = true
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
                VStack(alignment: .leading, spacing: 14) {
                    header

                    sectionLabel("Online Checkout")
                    if let business {
                        stripeCard(business)
                        payPalCard(business)
                    } else {
                        loadingCard
                    }

                    manualSection
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
        }
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            resolveBusiness()
            Task { await refreshStripeStatus() }
            Task { await refreshPayPalStatus() }
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
            Button("Copy Details") {
                UIPasteboard.general.string = payPalAlertDetails ?? ""
            }
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

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Manual Payments (Reconciliation)")

            DisclosureGroup(
                isExpanded: $manualExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let business {
                            squareCard(business)
                            cashAppCard(business)
                            venmoCard(business)
                            achCard(business)
                        } else {
                            loadingCard
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    HStack {
                        Text("Manual Payments (Reconciliation)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
            )
            .tint(.secondary)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
            )
        }
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
            primaryAction: .init(
                title: stripePrimaryActionTitle,
                isLoading: isStartingStripe,
                isDisabled: isStartingStripe || isLoadingStripe,
                action: { Task { await openStripeOnboarding() } }
            ),
            secondaryAction: .init(
                title: "Refresh Status",
                isLoading: false,
                isDisabled: isLoadingStripe || isStartingStripe,
                action: { Task { await refreshStripeStatus() } }
            )
        ) {
            if status.actionRequired {
                Text("Finish setup to enable payouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func payPalCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "paypal_logo",
            fallbackSymbol: "p.circle.fill",
            title: "PayPal",
            subtitle: "Platform-first PayPal checkout with optional fallback link.",
            tags: ["PayPal", "Cards"],
            statusText: payPalStatusLabel,
            statusStyle: payPalStatusStyle,
            primaryAction: .init(
                title: "Check Status",
                isLoading: isLoadingPayPalStatus,
                isDisabled: isLoadingPayPalStatus,
                action: { Task { await refreshPayPalStatus() } }
            ),
            secondaryAction: .init(
                title: "Refresh Status",
                isLoading: false,
                isDisabled: isLoadingPayPalStatus,
                action: { Task { await refreshPayPalStatus() } }
            )
        ) {
            if let lastChecked = payPalLastCheckedAt {
                Text("Last checked: \(lastChecked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !payPalPlatformEnabled && !isLoadingPayPalStatus {
                Text("Finish PayPal credentials in backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            .textFieldStyle(.roundedBorder)
        }
    }

    private func squareCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "square_logo",
            fallbackSymbol: "squareshape",
            title: "Square",
            subtitle: "Manual Square link with payment reconciliation approval.",
            tags: ["Cards", "Wallets"],
            statusText: business.squareEnabled ? "Enabled" : "Not connected",
            statusStyle: business.squareEnabled ? .enabled : .notConnected,
            enabledBinding: Binding(
                get: { business.squareEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.squareEnabled = newValue
                    }
                    save()
                }
            ),
            enabledLabel: "Enabled",
            hintWhenDisabled: "Enable to add your link/details."
        ) {
            TextField("https://square.link/...", text: Binding(
                get: { business.squareLink ?? "" },
                set: {
                    business.squareLink = normalizeURL($0)
                    save()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        }
    }

    private func cashAppCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "cashapp_logo",
            fallbackSymbol: "dollarsign.circle.fill",
            title: "Cash App",
            subtitle: "Accept Cash App with manual payment reconciliation.",
            tags: ["Cash App"],
            statusText: business.cashAppEnabled ? "Enabled" : "Not connected",
            statusStyle: business.cashAppEnabled ? .enabled : .notConnected,
            enabledBinding: Binding(
                get: { business.cashAppEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.cashAppEnabled = newValue
                    }
                    save()
                }
            ),
            enabledLabel: "Enabled",
            hintWhenDisabled: "Enable to add your link/details."
        ) {
            TextField("$handle or URL", text: Binding(
                get: { business.cashAppHandleOrLink ?? "" },
                set: {
                    business.cashAppHandleOrLink = normalizeCashAppInput($0)
                    save()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        }
    }

    private func venmoCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "venmo_logo",
            fallbackSymbol: "v.circle.fill",
            title: "Venmo",
            subtitle: "Use a Venmo profile link and reconcile manual reports.",
            tags: ["Venmo"],
            statusText: business.venmoEnabled ? "Enabled" : "Not connected",
            statusStyle: business.venmoEnabled ? .enabled : .notConnected,
            enabledBinding: Binding(
                get: { business.venmoEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.venmoEnabled = newValue
                    }
                    save()
                }
            ),
            enabledLabel: "Enabled",
            hintWhenDisabled: "Enable to add your link/details."
        ) {
            TextField("@handle or URL", text: Binding(
                get: { business.venmoHandleOrLink ?? "" },
                set: {
                    business.venmoHandleOrLink = normalizeVenmoInput($0)
                    save()
                }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        }
    }

    private func achCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "ach_logo",
            fallbackSymbol: "building.columns.fill",
            title: "ACH",
            subtitle: "Manual bank transfer with instructions and reconciliation.",
            tags: ["Bank Transfer"],
            statusText: business.achEnabled ? "Enabled" : "Not connected",
            statusStyle: business.achEnabled ? .enabled : .notConnected,
            enabledBinding: Binding(
                get: { business.achEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.achEnabled = newValue
                    }
                    save()
                }
            ),
            enabledLabel: "Enabled",
            hintWhenDisabled: "Enable to add your link/details.",
            primaryAction: .init(
                title: "Edit Instructions",
                isLoading: false,
                isDisabled: false,
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
        if payPalStatusError { return "Error" }
        guard payPalPlatformEnabled else { return "Not configured" }
        if let env = payPalEnv?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if env == "sandbox" { return "Sandbox" }
            if env == "live" { return "Live" }
        }
        return "Enabled"
    }

    private var payPalStatusStyle: ProviderStatusStyle {
        if isLoadingPayPalStatus { return .pending }
        if payPalStatusError { return .error }
        return payPalPlatformEnabled ? .active : .notConnected
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
            save()
        } catch {
            let details = errorDebugDetails(error)
            stripeAlertDetails = details
            stripeAlertMessage = stripeUserMessage(error: error, details: details)
            showStripeError = true
        }
    }

    private func refreshPayPalStatus() async {
        guard !isLoadingPayPalStatus else { return }
        isLoadingPayPalStatus = true
        payPalStatusError = false
        payPalLastCheckedAt = Date()
        defer { isLoadingPayPalStatus = false }

        do {
            let status = try await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            payPalPlatformEnabled = status.enabled
            payPalEnv = status.env
            business?.paypalEnabled = status.enabled
            save()
        } catch {
            payPalStatusError = true
            payPalAlertDetails = errorDebugDetails(error)
            payPalAlertMessage = "PayPal status unavailable. Please verify backend deployment and environment variables."
            showPayPalError = true
        }
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
    let enabledLabel: String
    let hintWhenDisabled: String?
    let primaryAction: ProviderAction?
    let secondaryAction: ProviderAction?
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
        enabledLabel: String = "Enabled",
        hintWhenDisabled: String? = nil,
        primaryAction: ProviderAction? = nil,
        secondaryAction: ProviderAction? = nil,
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
        self.enabledLabel = enabledLabel
        self.hintWhenDisabled = hintWhenDisabled
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusStyle.background))
                    .foregroundStyle(statusStyle.foreground)
                    .multilineTextAlignment(.trailing)
            }

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

            if let enabledBinding {
                Divider().opacity(0.35)
                HStack {
                    Text(enabledLabel)
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                }
            }

            let showDetailContent = enabledBinding?.wrappedValue ?? true
            if showDetailContent {
                content

                if primaryAction != nil || secondaryAction != nil {
                    HStack(spacing: 10) {
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

                        if let secondaryAction {
                            Button {
                                secondaryAction.action()
                            } label: {
                                HStack(spacing: 8) {
                                    if secondaryAction.isLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(secondaryAction.title)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(secondaryAction.isDisabled)
                        }
                    }
                }
            } else if let hintWhenDisabled, !hintWhenDisabled.isEmpty {
                Text(hintWhenDisabled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        )
    }
}
