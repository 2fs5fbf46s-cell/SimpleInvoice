import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UserNotifications

struct BusinessProfileView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var profile: BusinessProfile?
    @State private var business: Business?
    @State private var siteDraft: PublishedBusinessSite?
    @State private var siteServicesText: String = ""
    @State private var siteTeamText: String = ""
    @State private var siteGalleryPathsText: String = ""
    @State private var isPublishingSite = false
    @State private var siteAlertMessage: String?
    @State private var showSiteAlert = false
    @State private var showSitePreviewSafari = false
    @State private var sitePreviewURL: URL?
    @State private var siteDomainStatus: String = "unmapped"
    @State private var isCheckingSiteDomainStatus = false
    @State private var siteDomainCheckTask: Task<Void, Never>?
    @State private var siteDomainLastCheckedValue: String = ""
    @State private var siteDomainLastCheckedAt: Date = .distantPast

    @State private var paypalStatus: PayPalStatus?
    @State private var isLoadingPayPalStatus = false
    @State private var isStartingPayPalOnboarding = false
    @State private var paypalErrorMessage: String?
    @State private var showPayPalErrorAlert = false
    @State private var showPayPalSafari = false
    @State private var paypalOnboardingURL: URL?
    @State private var awaitingPayPalReturn = false
    @State private var stripeStatus: StripeConnectStatus?
    @State private var isLoadingStripeStatus = false
    @State private var isStartingStripeOnboarding = false
    @State private var stripeErrorMessage: String?
    @State private var showStripeErrorAlert = false
    @State private var showStripeSafari = false
    @State private var stripeOnboardingURL: URL?
    @State private var awaitingStripeReturn = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationMessage: String?
    @State private var showInvoiceTemplateSheet = false
    @State private var isSendingTestPush = false
    @State private var showNotificationAdvanced = false
    

    @State private var showEssentialsSection = true
    @State private var showBrandingSection = false
    @State private var showDefaultsSection = false
    @State private var showWebsiteSection = true
    @State private var showPaymentsSection = true
    @State private var showNotificationsSection = false
    @State private var showAdvancedSection = false
    @State private var showDebugMetadata = false
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

                    if let profile = self.profile {
                        bindWebsiteDraft(for: profile)
                    }
                } catch {
                    self.profile = profiles.first
                    self.business = businesses.first
                    if let profile = self.profile {
                        bindWebsiteDraft(for: profile)
                    }
                }
                Task { await refreshPayPalStatus() }
                Task { await refreshStripeStatus() }
                Task { await refreshNotificationStatus() }
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
        let base = ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            contentList(profile)
        }
        .navigationTitle("Business")
        .navigationBarTitleDisplayMode(.inline)
        return applyProfileLifecycle(to: base, profile: profile)
    }

    private func applyProfileLifecycle<V: View>(to view: V, profile: BusinessProfile) -> some View {
        let withLocalSaves = view
            .onChange(of: selectedLogoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        profile.logoData = data
                        try? modelContext.save()
                    }
                }
            }
            .onChange(of: profile.defaultThankYou) { _, _ in try? modelContext.save() }
            .onChange(of: profile.defaultTerms) { _, _ in try? modelContext.save() }
            .onChange(of: profile.catalogCategoriesText) { _, _ in try? modelContext.save() }
            .onChange(of: profile.invoicePrefix) { _, _ in try? modelContext.save() }
            .onChange(of: profile.nextInvoiceNumber) { _, _ in try? modelContext.save() }
            .onChange(of: profile.lastInvoiceYear) { _, _ in try? modelContext.save() }

        let withContextRefresh = withLocalSaves
            .onChange(of: activeBiz.activeBusinessID) { _, _ in
                if let bizID = activeBiz.activeBusinessID {
                    self.business = businesses.first(where: { $0.id == bizID })
                    if let refreshedProfile = profiles.first(where: { $0.businessID == bizID }) {
                        self.profile = refreshedProfile
                        bindWebsiteDraft(for: refreshedProfile)
                    }
                }
                Task { await refreshPayPalStatus() }
                Task { await refreshStripeStatus() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    handlePayPalReturnIfNeeded()
                    handleStripeReturnIfNeeded()
                    Task { await refreshNotificationStatus() }
                }
            }
            .onDisappear {
                siteDomainCheckTask?.cancel()
            }

        let withSheets = withContextRefresh
            .sheet(isPresented: $showInvoiceTemplateSheet) {
                NavigationStack {
                    InvoiceTemplatePickerSheet(
                        mode: .businessDefault,
                        businessDefault: businessDefaultTemplate,
                        currentEffective: businessDefaultTemplate,
                        currentSelection: businessDefaultTemplate,
                        onSelectTemplate: { selected in
                            guard let business else { return }
                            business.defaultInvoiceTemplateKey = selected.rawValue
                            try? modelContext.save()
                        },
                        onUseBusinessDefault: {
                            // No-op for business mode.
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showInvoiceTemplateSheet = false }
                        }
                    }
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
            .sheet(isPresented: $showStripeSafari) {
                if let url = stripeOnboardingURL {
                    SafariView(url: url) {
                        showStripeSafari = false
                        handleStripeReturnIfNeeded()
                    }
                } else {
                    Text("Unable to open Stripe onboarding.")
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showSitePreviewSafari) {
                if let url = sitePreviewURL {
                    SafariView(url: url) {
                        showSitePreviewSafari = false
                    }
                } else {
                    Text("Unable to open website preview.")
                        .foregroundStyle(.secondary)
                }
            }

        let withAlerts = withSheets
            .alert("Stripe Error", isPresented: $showStripeErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(stripeErrorMessage ?? "Something went wrong.")
            }
            .alert("PayPal Error", isPresented: $showPayPalErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(paypalErrorMessage ?? "Something went wrong.")
            }
            .alert("Website", isPresented: $showSiteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(siteAlertMessage ?? "Something went wrong.")
            }

        return withAlerts
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
        ScrollView {
            VStack(spacing: 14) {
                heroHeader(profile)
                essentialsCard(profile)
                brandingCard(profile)
                defaultsCard(profile)
                websitePublishingCard(profile)
                paymentsShortcutCard
                notificationsCard
                advancedOptionsCard(profile)

                Text("This info appears on invoice PDFs and client portal pages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .animation(.easeInOut(duration: 0.22), value: expansionAnimationKey)
    }

    private var expansionAnimationKey: Int {
        var value = 0
        value += showEssentialsSection ? 1 : 0
        value += showBrandingSection ? 2 : 0
        value += showDefaultsSection ? 4 : 0
        value += showWebsiteSection ? 8 : 0
        value += showPaymentsSection ? 16 : 0
        value += showNotificationsSection ? 32 : 0
        value += showAdvancedSection ? 64 : 0
        value += showDebugMetadata ? 128 : 0
        return value
    }

    // MARK: - Cards

    private func heroHeader(_ profile: BusinessProfile) -> some View {
        let name = profile.name.trimmed.isEmpty ? "Business Profile" : profile.name.trimmed
        let status = completionStatus(for: profile)
        return HeaderView(
            businessName: name,
            email: profile.email.trimmed.isEmpty ? nil : profile.email.trimmed,
            logoData: profile.logoData,
            statusText: status.text,
            statusColor: status.color
        )
    }

    private func essentialsCard(_ profile: BusinessProfile) -> some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showEssentialsSection) {
                VStack(spacing: 10) {
                    FieldRow(title: "Name") {
                        TextField("Business Name", text: Bindable(profile).name)
                    }
                    FieldRow(title: "Email") {
                        TextField("Email", text: Bindable(profile).email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                    }
                    FieldRow(title: "Phone") {
                        TextField("Phone", text: Bindable(profile).phone)
                            .keyboardType(.phonePad)
                    }
                    FieldRow(title: "Address", verticalAlignTop: true) {
                        TextField("Address", text: Bindable(profile).address, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Essentials", subtitle: "Public business info", systemImage: "building.2")
            }
            .tint(.secondary)
        }
    }

    private func brandingCard(_ profile: BusinessProfile) -> some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showBrandingSection) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                            if let logoData = profile.logoData,
                               let uiImage = UIImage(data: logoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Business Logo")
                                .font(.subheadline.weight(.semibold))
                            Text(profile.logoData == nil ? "No logo set" : "Logo set")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedLogoItem, matching: .images, photoLibrary: .shared()) {
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
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Branding", subtitle: "Logo and appearance", systemImage: "paintbrush.pointed")
            }
            .tint(.secondary)
        }
    }

    private func defaultsCard(_ profile: BusinessProfile) -> some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showDefaultsSection) {
                VStack(spacing: 12) {
                    Button {
                        showInvoiceTemplateSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Default Invoice Template")
                                    .font(.subheadline.weight(.semibold))
                                Text(businessDefaultTemplate.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    FieldRow(title: "Thank You", verticalAlignTop: true) {
                        TextField("Default Thank You", text: Bindable(profile).defaultThankYou, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    FieldRow(title: "Terms", verticalAlignTop: true) {
                        TextField("Default Terms & Conditions", text: Bindable(profile).defaultTerms, axis: .vertical)
                            .lineLimit(4...10)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Defaults", subtitle: "Pre-fill invoice values", systemImage: "text.badge.checkmark")
            }
            .tint(.secondary)
        }
    }

    private var businessDefaultTemplate: InvoiceTemplateKey {
        guard let business,
              let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) else {
            return .modern_clean
        }
        return key
    }

    private func websitePublishingCard(_ profile: BusinessProfile) -> some View {
        PremiumCard {
            NavigationLink {
                WebsiteCustomizationView()
            } label: {
                HStack {
                    SectionHeaderRow(
                        title: "Website & Portal",
                        subtitle: "Customize your public page",
                        systemImage: "globe.badge.chevron.backward"
                    )
                    Spacer()
                    if let draft = siteDraft {
                        switch draft.status {
                        case .draft:
                            StatusPill(text: "Draft", color: .secondary, systemImage: "circle.fill")
                        case .published:
                            StatusPill(text: "Published", color: SBWTheme.brandGreen, systemImage: "circle.fill")
                        case .error:
                            StatusPill(text: "Error", color: .red, systemImage: "circle.fill")
                        case .queued, .publishing:
                            StatusPill(text: "Updating", color: .orange, systemImage: "circle.fill")
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var paymentsCard: some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showPaymentsSection) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stripe")
                                .font(.subheadline.weight(.semibold))
                            Text(stripeStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isLoadingStripeStatus {
                            ProgressView()
                        } else {
                            stripeStatusPill
                        }
                    }

                    ActionButtonRow(
                        primaryTitle: stripePrimaryActionTitle,
                        primarySystemImage: "link",
                        primaryTint: SBWTheme.brandGreen,
                        primaryDisabled: isLoadingStripeStatus || isStartingStripeOnboarding,
                        secondaryTitle: "Refresh",
                        secondarySystemImage: "arrow.clockwise",
                        secondaryDisabled: isLoadingStripeStatus || isStartingStripeOnboarding,
                        onPrimaryTap: { Task { await startStripeOnboarding() } },
                        onSecondaryTap: { Task { await refreshStripeStatus() } }
                    )

                    Divider().overlay(Color.white.opacity(0.08))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PayPal (Platform)")
                                .font(.subheadline.weight(.semibold))
                            Text("Configured on server")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(text: "Server Configured", color: .secondary, systemImage: "server.rack")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PayPal.me (fallback)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if business != nil {
                            TextField("https://paypal.me/yourbusiness", text: paypalMeBinding)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .focused($paypalMeFocused)
                                .submitLabel(.done)
                                .onSubmit { normalizePayPalMeIfNeeded() }
                        } else {
                            Text("Select a business to edit PayPal.me.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Used only as fallback for client portal payments.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Payments", subtitle: "Stripe and PayPal controls", systemImage: "creditcard.fill")
            }
            .tint(.secondary)
        }
    }

    private var paymentsShortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderRow(
                title: "Payments",
                subtitle: "Manage setup in one place",
                systemImage: "creditcard.fill"
            )
            NavigationLink {
                SetupPaymentsView()
            } label: {
                SBWNavigationRow(
                    title: "Setup Payments",
                    subtitle: "Stripe, PayPal, Square, Cash App, Venmo, ACH"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var stripePrimaryActionTitle: String {
        switch stripeStatus?.onboardingStatus.lowercased() {
        case "active":
            return "Manage Stripe"
        case "needs_onboarding":
            return "Finish Setup"
        default:
            return "Connect Stripe"
        }
    }

    private var notificationsCard: some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showNotificationsSection) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Status")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        StatusPill(text: notificationStatusLabel, color: notificationStatusColor, systemImage: "bell.badge")
                    }

                    Button("Enable Notifications") {
                        Task { await enableNotificationsTapped() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await enablePushNotificationsTapped() }
                    } label: {
                        Label("Register for Push", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.bordered)

                    #if DEBUG
                    DisclosureGroup("Debug tools", isExpanded: $showNotificationAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                Task { await testLocalNotificationTapped() }
                            } label: {
                                Label("Test Local Notification", systemImage: "bell")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await sendTestPushTapped() }
                            } label: {
                                if isSendingTestPush {
                                    HStack {
                                        ProgressView()
                                        Text("Sending…")
                                    }
                                } else {
                                    Label("Send Test Push", systemImage: "paperplane")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSendingTestPush)
                        }
                        .padding(.top, 8)
                    }
                    .tint(.secondary)
                    #endif

                    if let notificationMessage, !notificationMessage.isEmpty {
                        Text(notificationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Notifications", subtitle: "Push and reminders", systemImage: "bell.fill")
            }
            .tint(.secondary)
        }
    }

    private var notificationStatusColor: Color {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return SBWTheme.brandGreen
        case .denied:
            return .red
        default:
            return .orange
        }
    }

    private func advancedOptionsCard(_ profile: BusinessProfile) -> some View {
        PremiumCard {
            DisclosureGroup(isExpanded: $showAdvancedSection) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Invoice Numbers")
                        .font(.subheadline.weight(.semibold))

                    FieldRow(title: "Prefix") {
                        TextField("Prefix (letters before the number)", text: Bindable(profile).invoicePrefix)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    Stepper(value: Bindable(profile).nextInvoiceNumber, in: 1...999999) {
                        Text("Next number: \(profile.nextInvoiceNumber)")
                    }

                    let year = Calendar.current.component(.year, from: .now)
                    Text("Example: \(profile.invoicePrefix)-\(year)-\(String(format: "%03d", profile.nextInvoiceNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        let currentYear = Calendar.current.component(.year, from: .now)
                        profile.lastInvoiceYear = currentYear
                        profile.nextInvoiceNumber = 1
                        try? modelContext.save()
                    } label: {
                        Label("Reset number to 001", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink("Switch business") {
                        BusinessSwitcherView()
                    }

                    DisclosureGroup("Debug / Metadata", isExpanded: $showDebugMetadata) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let id = activeBiz.activeBusinessID {
                                metadataRow("Active Business ID", id.uuidString)
                            }
                            metadataRow("Profile Business ID", profile.businessID.uuidString)
                            metadataRow("Stripe Account ID", business?.stripeAccountId ?? "Not linked")
                            metadataRow("Stripe Status", business?.stripeOnboardingStatus ?? "not_connected")
                            metadataRow("Website Handle", siteDraft?.handle ?? "N/A")
                            metadataRow("Domain Status", siteDomainStatusLabel)
                        }
                        .padding(.top, 8)
                    }
                    .tint(.secondary)
                }
                .padding(.top, 8)
            } label: {
                SectionHeaderRow(title: "Advanced", subtitle: "Invoice numbers and metadata", systemImage: "slider.horizontal.3")
            }
            .tint(.secondary)
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Status

    private func completionStatus(for profile: BusinessProfile) -> (text: String, color: Color, isComplete: Bool) {
        let nameOK = !profile.name.trimmed.isEmpty
        let emailOK = !profile.email.trimmed.isEmpty
        let phoneOK = !profile.phone.trimmed.isEmpty
        if nameOK && emailOK && phoneOK {
            return ("Complete", SBWTheme.brandGreen, true)
        }
        if nameOK && emailOK {
            return ("Incomplete", .orange, false)
        }
        return ("Action Needed", .red, false)
    }

    // MARK: - Website publishing

    private func websiteHandleBinding(_ draft: PublishedBusinessSite) -> Binding<String> {
        Binding(
            get: { draft.handle },
            set: { newValue in
                draft.handle = newValue
                BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
            }
        )
    }

    private func websiteAppNameBinding(_ draft: PublishedBusinessSite) -> Binding<String> {
        Binding(
            get: { draft.appName },
            set: { newValue in
                draft.appName = newValue
                BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
            }
        )
    }

    private func websiteDomainBinding(_ draft: PublishedBusinessSite) -> Binding<String> {
        Binding(
            get: { draft.publicSiteDomain ?? "" },
            set: { newValue in
                let normalized = PublishedBusinessSite.normalizePublicSiteDomain(newValue)
                draft.publicSiteDomain = normalized.isEmpty ? nil : normalized
                BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
                scheduleSiteDomainStatusCheck(force: false, debounced: true)
            }
        )
    }

    private func websiteIncludeWwwBinding(_ draft: PublishedBusinessSite) -> Binding<Bool> {
        Binding(
            get: { draft.includeWww },
            set: { newValue in
                draft.includeWww = newValue
                BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
            }
        )
    }

    private func websiteAboutBinding(_ draft: PublishedBusinessSite) -> Binding<String> {
        Binding(
            get: { draft.aboutUs },
            set: { newValue in
                draft.aboutUs = newValue
                BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
            }
        )
    }

    private func bindWebsiteDraft(for profile: BusinessProfile) {
        guard let bizID = activeBiz.activeBusinessID ?? business?.id else { return }
        let draft = BusinessSitePublishService.shared.draft(for: bizID, context: modelContext)

        if draft.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackName = business?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.appName = (fallbackName?.isEmpty == false) ? (fallbackName ?? "") : profile.name
        }
        if draft.handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.handle = PublishedBusinessSite.normalizeHandle(profile.name)
        }

        if draft.services.isEmpty {
            draft.services = PublishedBusinessSite.splitLines(profile.catalogCategoriesText)
        }
        if draft.aboutUs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.aboutUs = profile.defaultThankYou.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
        siteDraft = draft
        siteServicesText = PublishedBusinessSite.joinLines(draft.services)
        siteTeamText = PublishedBusinessSite.joinLines(draft.teamMembers)
        siteGalleryPathsText = PublishedBusinessSite.joinLines(draft.galleryLocalPaths)
        scheduleSiteDomainStatusCheck(force: false, debounced: true)
    }

    private func previewWebsiteTapped() {
        guard let siteDraft else { return }
        let normalized = PublishedBusinessSite.normalizeHandle(siteDraft.handle)
        guard !normalized.isEmpty else {
            siteAlertMessage = "Add a website handle before previewing."
            showSiteAlert = true
            return
        }

        siteDraft.handle = normalized
        BusinessSitePublishService.shared.saveDraftEdits(siteDraft, context: modelContext)
        sitePreviewURL = PortalBackend.shared.publicSiteURL(
            handle: normalized,
            customDomain: siteDraft.publicSiteDomain
        )
        showSitePreviewSafari = true
    }

    @MainActor
    private func publishWebsiteTapped(profile: BusinessProfile) async {
        guard let siteDraft else { return }
        guard !isPublishingSite else { return }
        isPublishingSite = true
        defer { isPublishingSite = false }

        siteDraft.services = PublishedBusinessSite.splitLines(siteServicesText)
        siteDraft.teamMembers = PublishedBusinessSite.splitLines(siteTeamText)
        siteDraft.galleryLocalPaths = PublishedBusinessSite.splitLines(siteGalleryPathsText)

        do {
            try await BusinessSitePublishService.shared.queuePublish(
                draft: siteDraft,
                profile: profile,
                business: business,
                context: modelContext
            )
            scheduleSiteDomainStatusCheck(force: true, debounced: false)
        } catch {
            siteAlertMessage = error.localizedDescription
            showSiteAlert = true
        }
    }

    private var siteDomainStatusLabel: String {
        switch siteDomainStatus {
        case "active":
            return "Active"
        case "dns_pending":
            return "DNS pending"
        default:
            return "Unmapped"
        }
    }

    private var siteDomainStatusColor: Color {
        switch siteDomainStatus {
        case "active":
            return SBWTheme.brandGreen
        case "dns_pending":
            return .orange
        default:
            return .secondary
        }
    }

    private func scheduleSiteDomainStatusCheck(force: Bool, debounced: Bool) {
        siteDomainCheckTask?.cancel()
        guard let domain = siteDraft?.publicSiteDomain?.trimmingCharacters(in: .whitespacesAndNewlines),
              !domain.isEmpty else {
            siteDomainStatus = "unmapped"
            isCheckingSiteDomainStatus = false
            return
        }

        if !force,
           siteDomainLastCheckedValue == domain,
           Date().timeIntervalSince(siteDomainLastCheckedAt) < 8 {
            return
        }

        siteDomainCheckTask = Task {
            if debounced {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            isCheckingSiteDomainStatus = true
            let result = await PortalBackend.shared.verifyPublicSiteDomain(domain: domain)
            guard !Task.isCancelled else { return }
            siteDomainStatus = result.status
            siteDomainLastCheckedValue = domain
            siteDomainLastCheckedAt = .now
            isCheckingSiteDomainStatus = false
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

    // MARK: - Payments helpers

    private var stripeStatusText: String {
        if isLoadingStripeStatus {
            return "Checking connection…"
        }
        guard let status = stripeStatus else { return "Not connected" }
        switch status.onboardingStatus.lowercased() {
        case "active":
            return "Active"
        case "needs_onboarding":
            return "Needs onboarding"
        case "disabled":
            return "Disabled"
        default:
            return "Not connected"
        }
    }

    private var stripeStatusPill: some View {
        let normalized = stripeStatus?.onboardingStatus.lowercased() ?? "not_connected"
        let text: String
        let color: Color

        switch normalized {
        case "active":
            text = "Active"
            color = SBWTheme.brandGreen
        case "needs_onboarding":
            text = "Needs onboarding"
            color = .orange
        case "disabled":
            text = "Disabled"
            color = .red
        default:
            text = "Not connected"
            color = .secondary
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

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

    private var websiteStatusPill: some View {
        let meta = websiteStatusMeta

        return Text(meta.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(meta.color.opacity(0.15))
            .foregroundStyle(meta.color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var websiteStatusMeta: (label: String, color: Color) {
        switch siteDraft?.status ?? .draft {
        case .draft:
            return ("Draft", .secondary)
        case .queued:
            return ("Queued", .orange)
        case .publishing:
            return ("Publishing", SBWTheme.brandBlue)
        case .published:
            return ("Published", SBWTheme.brandGreen)
        case .error:
            return ("Error", .red)
        }
    }

    private var notificationStatusLabel: String {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized, .provisional, .ephemeral:
            return "Authorized"
        @unknown default:
            return "Not Determined"
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationAuthorizationStatus = await NotificationManager.shared.getAuthorizationStatus()
    }

    @MainActor
    private func enableNotificationsTapped() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        await refreshNotificationStatus()
        if granted {
            await refreshLocalRemindersNow()
            notificationMessage = "Notifications enabled. Local reminders synced."
        } else {
            notificationMessage = "Notifications were not enabled."
        }
    }

    @MainActor
    private func testLocalNotificationTapped() async {
        let status = await NotificationManager.shared.getAuthorizationStatus()
        if status == .denied {
            notificationMessage = "Notification permission is denied. Enable it in Settings."
            notificationAuthorizationStatus = status
            return
        }
        if status == .notDetermined {
            _ = await NotificationManager.shared.requestAuthorization()
        }
        await NotificationManager.shared.scheduleTestLocalNotification()
        await refreshNotificationStatus()
        notificationMessage = "Test notification scheduled for ~5 seconds."
    }

    @MainActor
    private func enablePushNotificationsTapped() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        await refreshNotificationStatus()
        let canRegister = granted || [.authorized, .provisional, .ephemeral].contains(notificationAuthorizationStatus)
        guard canRegister else {
            notificationMessage = "Push registration skipped because notifications are not authorized."
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        await refreshLocalRemindersNow()
        notificationMessage = "Requested APNs registration. Local reminders synced."
    }

    @MainActor
    private func sendTestPushTapped() async {
        guard !isSendingTestPush else { return }
        guard let businessId = activeBiz.activeBusinessID else {
            notificationMessage = "No active business selected."
            return
        }

        isSendingTestPush = true
        defer { isSendingTestPush = false }

        do {
            try await PortalBackend.shared.sendTestPush(businessId: businessId.uuidString)
            notificationMessage = "Test push request sent. Check this device."
        } catch {
            notificationMessage = "Failed to send test push: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshLocalRemindersNow() async {
        await LocalReminderScheduler.shared.refreshReminders(
            modelContext: modelContext,
            activeBusinessID: activeBiz.activeBusinessID
        )
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
            if case PortalBackendError.http(let code, _, _) = error, code == 404 || code == 405 {
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

    @MainActor
    private func refreshStripeStatus() async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        guard !isLoadingStripeStatus else { return }

        isLoadingStripeStatus = true
        defer { isLoadingStripeStatus = false }

        do {
            let status = try await PortalPaymentsAPI.shared.fetchStripeConnectStatus(businessId: businessId)
            stripeStatus = status
            if let business = businesses.first(where: { $0.id == businessId }) {
                business.stripeAccountId = status.stripeAccountId
                business.stripeOnboardingStatus = status.onboardingStatus
                business.stripeChargesEnabled = status.chargesEnabled
                business.stripePayoutsEnabled = status.payoutsEnabled
                try? modelContext.save()
                self.business = business
            }
        } catch {
            stripeErrorMessage = error.localizedDescription
            showStripeErrorAlert = true
        }
    }

    @MainActor
    private func startStripeOnboarding() async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        guard !isStartingStripeOnboarding else { return }

        isStartingStripeOnboarding = true
        defer { isStartingStripeOnboarding = false }

        do {
            let returnURL = PortalConfig.shared.baseURL.appendingPathComponent("/portal/admin/settings")
            let url = try await PortalPaymentsAPI.shared.startStripeConnect(
                businessId: businessId,
                returnURL: returnURL
            )
            stripeOnboardingURL = url
            showStripeSafari = true
            awaitingStripeReturn = true
        } catch {
            stripeErrorMessage = error.localizedDescription
            showStripeErrorAlert = true
        }
    }

    @MainActor
    private func handleStripeReturnIfNeeded() {
        guard awaitingStripeReturn else { return }
        awaitingStripeReturn = false
        Task { await refreshStripeStatus() }
    }
}

private struct HeaderView: View {
    let businessName: String
    let email: String?
    let logoData: Data?
    let statusText: String
    let statusColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(businessName)
                    .font(.system(size: 34, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text("Invoices • Portal • Emails")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(text: statusText, color: statusColor, systemImage: "circle.fill")
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    if let logoData, let image = UIImage(data: logoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.92))
                SBWTheme.brandGradient
                    .opacity(0.14)
                    .blur(radius: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct PremiumCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private struct SectionHeaderRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

private struct ActionButtonRow: View {
    let primaryTitle: String
    let primarySystemImage: String
    let primaryTint: Color
    let primaryDisabled: Bool
    let secondaryTitle: String
    let secondarySystemImage: String
    let secondaryDisabled: Bool
    let onPrimaryTap: () -> Void
    let onSecondaryTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrimaryTap) {
                Label(primaryTitle, systemImage: primarySystemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryTint)
            .disabled(primaryDisabled)

            Button(action: onSecondaryTap) {
                Label(secondaryTitle, systemImage: secondarySystemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(secondaryDisabled)
        }
    }
}

private struct FieldRow<Content: View>: View {
    let title: String
    var verticalAlignTop: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: verticalAlignTop ? .top : .center, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
                .padding(.top, verticalAlignTop ? 7 : 0)

            content()
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
