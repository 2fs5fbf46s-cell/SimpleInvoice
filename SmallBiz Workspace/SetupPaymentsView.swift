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

    @State private var isLoadingPayPalPlatform = false
    @State private var payPalPlatformEnabled = false
    @State private var payPalEnv: String?
    @State private var payPalAlertMessage: String?
    @State private var payPalAlertDetails: String?
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
                            .padding(.vertical, 24)
                    }
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
        .alert("Stripe", isPresented: $showStripeError) {
            #if DEBUG
            if let details = stripeAlertDetails, !details.isEmpty {
                Button("Copy Details") {
                    UIPasteboard.general.string = details
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(stripeAlertMessage ?? "Payment service is unavailable. Please try again.")
        }
        .alert("PayPal", isPresented: $showPayPalError) {
            #if DEBUG
            if let details = payPalAlertDetails, !details.isEmpty {
                Button("Copy Details") {
                    UIPasteboard.general.string = details
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(payPalAlertMessage ?? "Payment service is unavailable. Please try again.")
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
        return providerCardContainer {
            providerHeader(
                logo: "stripe_logo",
                title: "Stripe Connect",
                status: status.label
            )
            providerDescription("Accept cards and wallet payments with connected payouts.")
            methodsRow(["Visa", "Mastercard", "Apple Pay"])
            feeNote("Fees vary by region and card type.")
            actionButtonsRow(
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
    }

    private func payPalCard(_ business: Business) -> some View {
        providerCardContainer {
            providerHeader(
                logo: "paypal_logo",
                title: "PayPal",
                status: payPalPlatformEnabled ? "Enabled (backend env)" : "Unavailable"
            )
            providerDescription("Platform-first PayPal checkout with optional fallback link.")
            methodsRow(["PayPal", "Cards"])
            feeNote("PayPal fees apply per transaction.")

            actionButtonsRow(
                primaryTitle: isLoadingPayPalPlatform ? "Checking…" : "Check Status",
                secondaryTitle: nil,
                primaryDisabled: isLoadingPayPalPlatform,
                secondaryDisabled: true
            ) {
                await refreshPayPalPlatformStatus()
            } onSecondaryTap: {
                // no-op
            }

            if let env = payPalEnv, !env.isEmpty {
                Text("Environment: \(env)")
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
        providerCardContainer {
            providerHeader(
                logo: "square_logo",
                title: "Square",
                status: business.squareEnabled ? "Enabled" : "Not connected"
            )
            providerDescription("Manual Square link with payment reconciliation approval.")
            methodsRow(["Cards", "Wallets"])
            feeNote("Use your hosted Square payment link.")
            Divider().opacity(0.35)

            toggleRow("Enable Square", isOn: Binding(
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
        providerCardContainer {
            providerHeader(
                logo: "cashapp_logo",
                title: "Cash App",
                status: business.cashAppEnabled ? "Enabled" : "Not connected"
            )
            providerDescription("Accept Cash App with manual payment reconciliation.")
            methodsRow(["Cash App"])
            feeNote("Customers can pay with your Cash App profile.")
            Divider().opacity(0.35)

            toggleRow("Enable Cash App", isOn: Binding(
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
        providerCardContainer {
            providerHeader(
                logo: "venmo_logo",
                title: "Venmo",
                status: business.venmoEnabled ? "Enabled" : "Not connected"
            )
            providerDescription("Use a Venmo profile link and reconcile manual reports.")
            methodsRow(["Venmo"])
            feeNote("Use your public Venmo profile link.")
            Divider().opacity(0.35)

            toggleRow("Enable Venmo", isOn: Binding(
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
        providerCardContainer {
            providerHeader(
                logo: "ach_logo",
                title: "ACH",
                status: business.achEnabled ? "Enabled" : "Not connected"
            )
            providerDescription("Manual bank transfer with instructions and reconciliation.")
            methodsRow(["Bank Transfer"])
            feeNote("Store only account/routing last 4 digits.")
            Divider().opacity(0.35)

            toggleRow("Enable ACH", isOn: Binding(
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

    private func providerCardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        )
    }

    private func providerHeader(logo: String, title: String, status: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
            }

            Spacer(minLength: 8)

            statusPill(status)
        }
    }

    private func providerDescription(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func methodsRow(_ chips: [String]) -> some View {
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

    private func feeNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private func actionButtonsRow(
        primaryTitle: String,
        secondaryTitle: String?,
        primaryDisabled: Bool,
        secondaryDisabled: Bool,
        onPrimaryTap: @escaping () async -> Void,
        onSecondaryTap: @escaping () async -> Void
    ) -> some View {
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

    private func statusPill(_ text: String) -> some View {
        let colors = SBWTheme.chip(forStatus: text.uppercased())
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
            .multilineTextAlignment(.trailing)
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
            presentStripeError(error)
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
            presentStripeError(error)
        }
    }

    private func refreshPayPalPlatformStatus() async {
        guard !isLoadingPayPalPlatform else { return }
        isLoadingPayPalPlatform = true
        defer { isLoadingPayPalPlatform = false }
        do {
            let status = try await PortalPaymentsAPI.shared.fetchPayPalPlatformStatus()
            payPalPlatformEnabled = status.enabled
            payPalEnv = status.env
            business?.paypalEnabled = status.enabled
            save()
        } catch {
            presentPayPalError(error)
        }
    }

    private func presentStripeError(_ error: Error) {
        let details = errorDebugDetails(error)
        stripeAlertDetails = details
        stripeAlertMessage = sanitizeErrorMessage(details, fallback: "Unable to connect to Stripe right now. Please try again.")
        showStripeError = true
    }

    private func presentPayPalError(_ error: Error) {
        let details = errorDebugDetails(error)
        payPalAlertDetails = details
        payPalAlertMessage = "PayPal status unavailable. Please verify backend deployment and environment variables."
        showPayPalError = true
    }

    private func errorDebugDetails(_ error: Error) -> String {
        if let serviceError = error as? PaymentServiceResponseError {
            return serviceError.details
        }
        return (error as NSError).localizedDescription
    }

    private func sanitizeErrorMessage(_ details: String, fallback: String) -> String {
        let lowered = details.lowercased()
        if lowered.contains("<html") || lowered.contains("<!doctype") {
            return "Payment service is unavailable (unexpected response). Please try again."
        }
        return fallback
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
