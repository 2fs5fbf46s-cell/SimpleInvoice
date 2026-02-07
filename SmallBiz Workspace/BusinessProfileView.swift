import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct BusinessProfileView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var profile: BusinessProfile?
    @State private var business: Business?

    @State private var paypalStatus: PayPalStatus?
    @State private var isLoadingPayPalStatus = false
    @State private var isStartingPayPalOnboarding = false
    @State private var paypalErrorMessage: String?
    @State private var showPayPalErrorAlert = false
    @State private var showPayPalSafari = false
    @State private var paypalOnboardingURL: URL?
    @State private var awaitingPayPalReturn = false

    @State private var showAdvancedOptions = false
    @FocusState private var paypalMeFocused: Bool

    var body: some View {
        contentView
            .onAppear {
                do {
                    try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)

                    guard let bizID = activeBiz.activeBusinessID else { return }

                    if let existing = profiles.first(where: { $0.businessID == bizID }) {
                        self.profile = existing
                    } else {
                        let created = BusinessProfile(businessID: bizID)
                        modelContext.insert(created)
                        try? modelContext.save()
                        self.profile = created
                    }

                    if let existingBiz = businesses.first(where: { $0.id == bizID }) {
                        self.business = existingBiz
                    } else {
                        self.business = businesses.first
                    }
                } catch {
                    self.profile = profiles.first
                    self.business = businesses.first
                }
                Task { await refreshPayPalStatus() }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if let profile {
            profileView(profile)
        } else {
            ProgressView("Loading…")
                .navigationTitle("Business Profile")
        }
    }

    private func profileView(_ profile: BusinessProfile) -> some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            contentList(profile)
        }
        .navigationTitle("Business Profile")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            pinnedHeader(profile)
        }
        .onChange(of: selectedLogoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    profile.logoData = data
                    try? modelContext.save()
                }
            }
        }
        // ✅ auto-save for text changes
        .onChange(of: profile.defaultThankYou) { _, _ in try? modelContext.save() }
        .onChange(of: profile.defaultTerms) { _, _ in try? modelContext.save() }
        .onChange(of: profile.catalogCategoriesText) { _, _ in try? modelContext.save() }
        .onChange(of: profile.invoicePrefix) { _, _ in try? modelContext.save() }
        .onChange(of: profile.nextInvoiceNumber) { _, _ in try? modelContext.save() }
        .onChange(of: profile.lastInvoiceYear) { _, _ in try? modelContext.save() }
        .onChange(of: activeBiz.activeBusinessID) { _, _ in
            if let bizID = activeBiz.activeBusinessID {
                self.business = businesses.first(where: { $0.id == bizID })
            }
            Task { await refreshPayPalStatus() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                handlePayPalReturnIfNeeded()
            }
        }
        .sheet(isPresented: $showPayPalSafari) {
            if let url = paypalOnboardingURL {
                SafariView(url: url) {
                    showPayPalSafari = false
                    handlePayPalReturnIfNeeded()
                }
            } else {
                Text("Unable to open PayPal onboarding.")
                    .foregroundStyle(.secondary)
            }
        }
        .alert("PayPal Error", isPresented: $showPayPalErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paypalErrorMessage ?? "Something went wrong.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    normalizePayPalMeIfNeeded()
                    paypalMeFocused = false
                }
            }
        }
    }

    private func contentList(_ profile: BusinessProfile) -> some View {
        List {
            essentialsCard(profile)
            brandingCard(profile)
            defaultsCard(profile)
            paymentsCard
            advancedOptionsCard(profile)

            Text("This info will appear on your invoice PDFs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sbwCardRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header

    private func pinnedHeader(_ profile: BusinessProfile) -> some View {
        let name = profile.name.trimmed.isEmpty ? "Business Profile" : profile.name.trimmed
        let status = completionStatus(for: profile)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Invoices • Portal • Emails")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill(text: status.text, color: status.color)
            }

            if !status.isComplete {
                inlineWarning(
                    "Add a business name and email to complete your profile.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Cards

    private func essentialsCard(_ profile: BusinessProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("Essentials", subtitle: "Public business info")

            TextField("Business Name", text: Bindable(profile).name)
            TextField("Email", text: Bindable(profile).email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            TextField("Phone", text: Bindable(profile).phone)
                .keyboardType(.phonePad)
            TextField("Address", text: Bindable(profile).address, axis: .vertical)
                .lineLimit(2...6)
        }
        .sbwCardRow()
    }

    private func brandingCard(_ profile: BusinessProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Branding", subtitle: "Logo and appearance")

            if let logoData = profile.logoData,
               let uiImage = UIImage(data: logoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .cornerRadius(12)
                    .padding(.vertical, 4)
            } else {
                ContentUnavailableView(
                    "No Logo",
                    systemImage: "photo",
                    description: Text("Select a logo to appear on your invoices.")
                )
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedLogoItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label("Choose Logo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                if profile.logoData != nil {
                    Button(role: .destructive) {
                        profile.logoData = nil
                        selectedLogoItem = nil
                        try? modelContext.save()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sbwCardRow()
    }

    private func defaultsCard(_ profile: BusinessProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("Defaults", subtitle: "Pre-fill new invoices")

            TextField("Default Thank You", text: Bindable(profile).defaultThankYou, axis: .vertical)
                .lineLimit(2...6)

            TextField("Default Terms & Conditions", text: Bindable(profile).defaultTerms, axis: .vertical)
                .lineLimit(4...10)
        }
        .sbwCardRow()
    }

    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Payments", subtitle: "Manage payment connections")

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SBWTheme.brandBlue.opacity(0.15))
                    Image(systemName: "creditcard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBWTheme.brandBlue)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("PayPal")
                        .font(.system(size: 16, weight: .semibold))

                    Text(paypalStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoadingPayPalStatus {
                    ProgressView()
                } else {
                    statusPillView
                }
            }

            if paypalStatus?.connected == true {
                if let last4 = paypalStatus?.merchantIdLast4, !last4.isEmpty {
                    Text("Merchant ID ••••\(last4)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    // Optional: backend disconnect endpoint not available yet.
                } label: {
                    Label("Disconnect PayPal", systemImage: "link.badge.minus")
                }
                .disabled(true)
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await startPayPalOnboarding() }
                } label: {
                    Label("Connect PayPal", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(isStartingPayPalOnboarding || isLoadingPayPalStatus)
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("PayPal.me (fallback)")
                    .font(.subheadline.weight(.semibold))

                Text("Used for PayPal payments in the client portal (fallback).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let _ = business {
                    TextField(
                        "https://paypal.me/yourbusiness",
                        text: paypalMeBinding
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($paypalMeFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        normalizePayPalMeIfNeeded()
                    }
                } else {
                    Text("Select a business to edit PayPal.me.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Paste a full PayPal.me link or just your handle (no @).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sbwCardRow()
    }

    private func advancedOptionsCard(_ profile: BusinessProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    Text("Invoice Numbers")
                        .font(.headline)

                    TextField("Prefix (letters before the number)", text: Bindable(profile).invoicePrefix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Stepper(value: Bindable(profile).nextInvoiceNumber, in: 1...999999) {
                        Text("Next number: \(profile.nextInvoiceNumber)")
                    }

                    let year = Calendar.current.component(.year, from: .now)
                    Text("Example: \(profile.invoicePrefix)-\(year)-\(String(format: "%03d", profile.nextInvoiceNumber))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        let year = Calendar.current.component(.year, from: .now)
                        profile.lastInvoiceYear = year
                        profile.nextInvoiceNumber = 1
                        try? modelContext.save()
                    } label: {
                        Label("Reset number to 001", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Text("Workspace")
                        .font(.headline)

                    NavigationLink("Switch business") {
                        BusinessSwitcherView()
                    }

                    if let id = activeBiz.activeBusinessID {
                        Text("Active ID: \(id.uuidString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text("Advanced Options")
                    .font(.headline)
            }
        }
        .sbwCardRow()
    }

    // MARK: - Status

    private func completionStatus(for profile: BusinessProfile) -> (text: String, color: Color, isComplete: Bool) {
        let nameOK = !profile.name.trimmed.isEmpty
        let emailOK = !profile.email.trimmed.isEmpty
        if nameOK && emailOK {
            return ("Complete", SBWTheme.brandGreen, true)
        }
        return ("Needs Attention", .orange, false)
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func inlineWarning(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cardHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - PayPal.me helpers

    private var paypalMeBinding: Binding<String> {
        Binding(
            get: { business?.paypalMeUrl ?? "" },
            set: { newValue in
                business?.paypalMeUrl = newValue
            }
        )
    }

    private func normalizePayPalMeIfNeeded() {
        guard let business else { return }
        let normalized = normalizePayPalMe(business.paypalMeUrl)
        if normalized != business.paypalMeUrl {
            business.paypalMeUrl = normalized
        }
        try? modelContext.save()
    }

    private func normalizePayPalMe(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var value = trimmed
        if !value.lowercased().hasPrefix("http") {
            value = "https://paypal.me/\(value)"
        }

        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    // MARK: - PayPal helpers

    private var paypalStatusText: String {
        if isLoadingPayPalStatus {
            return "Checking connection…"
        }
        guard let status = paypalStatus else { return "Not connected" }
        if status.connected {
            if let last4 = status.merchantIdLast4, !last4.isEmpty {
                return "Connected ••••\(last4)"
            }
            return "Connected"
        }
        return "Not connected"
    }

    @ViewBuilder
    private var statusPillView: some View {
        let connected = paypalStatus?.connected == true
        let text = connected ? "Connected" : "Not connected"
        let color = connected ? SBWTheme.brandGreen : Color.secondary

        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @MainActor
    private func refreshPayPalStatus() async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        guard !isLoadingPayPalStatus else { return }

        isLoadingPayPalStatus = true
        defer { isLoadingPayPalStatus = false }

        do {
            paypalStatus = try await PortalPaymentsAPI.shared.fetchPayPalStatus(businessId: businessId)
        } catch {
            if case PortalBackendError.http(let code, _) = error, code == 404 || code == 405 {
                paypalStatus = PayPalStatus(connected: false, merchantIdLast4: nil, merchantIdFull: nil)
                return
            }
            paypalErrorMessage = error.localizedDescription
            showPayPalErrorAlert = true
        }
    }

    @MainActor
    private func startPayPalOnboarding() async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        guard !isStartingPayPalOnboarding else { return }

        isStartingPayPalOnboarding = true
        defer { isStartingPayPalOnboarding = false }

        do {
            let url = try await PortalPaymentsAPI.shared.createPayPalReferral(businessId: businessId)
            paypalOnboardingURL = url
            showPayPalSafari = true
            awaitingPayPalReturn = true
        } catch {
            paypalErrorMessage = error.localizedDescription
            showPayPalErrorAlert = true
        }
    }

    @MainActor
    private func handlePayPalReturnIfNeeded() {
        guard awaitingPayPalReturn else { return }
        awaitingPayPalReturn = false
        Task { await refreshPayPalStatus() }
    }
}

private struct SBWCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func sbwCardRow() -> some View {
        modifier(SBWCardRow())
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
