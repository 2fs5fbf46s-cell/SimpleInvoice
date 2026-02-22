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

    @State private var manualExpanded = false
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(stripeAlertMessage ?? "Unable to connect to Stripe right now. Please try again.")
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

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manualExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("Manual Payments (Reconciliation)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: manualExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if manualExpanded {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

    private func stripeCard(_ business: Business) -> some View {
        let status = stripeState
        return PaymentProviderCard(
            logoName: "stripe_logo",
            fallbackSymbol: "creditcard.fill",
            title: "Stripe Connect",
            subtitle: "Accept cards and wallet payments with connected payouts.",
            statusText: status.label,
            statusStyle: status.style
        ) {
            chipRow(["Visa", "Mastercard", "Apple Pay"])

            HStack(spacing: 10) {
                Button(isStartingStripe ? "Opening…" : (status.isConnected ? "Manage" : "Connect")) {
                    Task { await startStripe() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(isStartingStripe || isLoadingStripe)

                Button("Refresh Status") {
                    Task { await refreshStripeStatus() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingStripe || isStartingStripe)
            }
        }
    }

    private func payPalCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "paypal_logo",
            fallbackSymbol: "p.circle.fill",
            title: "PayPal",
            subtitle: "Platform-first PayPal checkout with optional fallback link.",
            statusText: payPalStatusLabel,
            statusStyle: payPalStatusStyle
        ) {
            chipRow(["PayPal", "Cards"])

            HStack(spacing: 10) {
                Button {
                    Task { await refreshPayPalStatus() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingPayPalStatus {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Check Status")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(isLoadingPayPalStatus)

                Button("Refresh Status") {
                    Task { await refreshPayPalStatus() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingPayPalStatus)
            }

            if let lastChecked = payPalLastCheckedAt {
                Text("Last checked: \(lastChecked.formatted(date: .omitted, time: .shortened))")
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
            statusText: business.squareEnabled ? "Enabled" : "Not connected",
            statusStyle: business.squareEnabled ? .enabled : .notConnected
        ) {
            chipRow(["Cards", "Wallets"])
            Divider().opacity(0.35)
            manualToggleRow("Enable Square", isOn: Binding(
                get: { business.squareEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.squareEnabled = newValue
                    }
                    save()
                }
            ))

            if business.squareEnabled {
                VStack(alignment: .leading, spacing: 12) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func cashAppCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "cashapp_logo",
            fallbackSymbol: "dollarsign.circle.fill",
            title: "Cash App",
            subtitle: "Accept Cash App with manual payment reconciliation.",
            statusText: business.cashAppEnabled ? "Enabled" : "Not connected",
            statusStyle: business.cashAppEnabled ? .enabled : .notConnected
        ) {
            chipRow(["Cash App"])
            Divider().opacity(0.35)
            manualToggleRow("Enable Cash App", isOn: Binding(
                get: { business.cashAppEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.cashAppEnabled = newValue
                    }
                    save()
                }
            ))

            if business.cashAppEnabled {
                VStack(alignment: .leading, spacing: 12) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func venmoCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "venmo_logo",
            fallbackSymbol: "v.circle.fill",
            title: "Venmo",
            subtitle: "Use a Venmo profile link and reconcile manual reports.",
            statusText: business.venmoEnabled ? "Enabled" : "Not connected",
            statusStyle: business.venmoEnabled ? .enabled : .notConnected
        ) {
            chipRow(["Venmo"])
            Divider().opacity(0.35)
            manualToggleRow("Enable Venmo", isOn: Binding(
                get: { business.venmoEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.venmoEnabled = newValue
                    }
                    save()
                }
            ))

            if business.venmoEnabled {
                VStack(alignment: .leading, spacing: 12) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func achCard(_ business: Business) -> some View {
        PaymentProviderCard(
            logoName: "ach_logo",
            fallbackSymbol: "building.columns.fill",
            title: "ACH",
            subtitle: "Manual bank transfer with instructions and reconciliation.",
            statusText: business.achEnabled ? "Enabled" : "Not connected",
            statusStyle: business.achEnabled ? .enabled : .notConnected
        ) {
            chipRow(["Bank Transfer"])
            Divider().opacity(0.35)
            manualToggleRow("Enable ACH", isOn: Binding(
                get: { business.achEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        business.achEnabled = newValue
                    }
                    save()
                }
            ))

            if business.achEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Edit Instructions") {
                        showingACHSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func chipRow(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
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

    private func manualToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private var stripeState: (label: String, style: ProviderStatusStyle, isConnected: Bool) {
        let accountId = stripeStatus?.stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if accountId.isEmpty { return ("Not connected", .notConnected, false) }
        if stripeStatus?.chargesEnabled == true && stripeStatus?.payoutsEnabled == true {
            return ("Active", .active, true)
        }
        return ("Pending", .pending, true)
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
            stripeAlertDetails = errorDebugDetails(error)
            stripeAlertMessage = "Unable to connect to Stripe right now. Please try again."
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
            stripeAlertDetails = errorDebugDetails(error)
            stripeAlertMessage = "Unable to connect to Stripe right now. Please try again."
            showStripeError = true
        }
    }

    private func refreshPayPalStatus() async {
        guard !isLoadingPayPalStatus else { return }
        isLoadingPayPalStatus = true
        payPalStatusError = false
        defer { isLoadingPayPalStatus = false }

        do {
            let status = try await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            payPalPlatformEnabled = status.enabled
            payPalEnv = status.env
            payPalLastCheckedAt = Date()
            business?.paypalEnabled = status.enabled
            save()
        } catch {
            payPalStatusError = true
            payPalLastCheckedAt = Date()
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

private struct PaymentProviderCard<Content: View>: View {
    let logoName: String?
    let fallbackSymbol: String
    let title: String
    let subtitle: String
    let statusText: String
    let statusStyle: ProviderStatusStyle
    @ViewBuilder let content: Content

    init(
        logoName: String?,
        fallbackSymbol: String,
        title: String,
        subtitle: String,
        statusText: String,
        statusStyle: ProviderStatusStyle,
        @ViewBuilder content: () -> Content
    ) {
        self.logoName = logoName
        self.fallbackSymbol = fallbackSymbol
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusStyle = statusStyle
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

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        )
    }
}
