import SwiftUI
import SwiftData
import UIKit

struct BookingPortalView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var profile: BusinessProfile?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showShare = false
    @State private var showSafari = false
    @State private var showRegenerateConfirm = false
    @State private var didAttemptSlug = false
    @State private var showCopyToast = false
    @State private var toastMessage: String = "Copied to clipboard"
    @State private var showErrorAlert = false
    @State private var showMissingEmailAlert = false
    @State private var showBusinessProfile = false
    @State private var isSyncingSettings = false
    @State private var lastSyncedAt: Date? = nil
    @State private var showActions = true
    @State private var showQuickSetup = true
    @State private var showAdvanced = false

    private let bookingBaseURL = "https://book.smallbizworkspace.com"

    private var bookingSlug: String {
        profile?.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var bookingURLString: String {
        guard !bookingSlug.isEmpty else { return "Not generated yet" }
        return "\(bookingBaseURL)/\(bookingSlug)"
    }

    private var bookingURL: URL? {
        guard !bookingSlug.isEmpty else { return nil }
        return URL(string: bookingURLString)
    }

    var body: some View {
        Group {
            if let currentProfile = profile {
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    SBWTheme.brandGradient
                        .opacity(SBWTheme.headerWashOpacity)
                        .blur(radius: SBWTheme.headerWashBlur)
                        .frame(height: SBWTheme.headerWashHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 14) {
                            hero(currentProfile)
                            actionsCard
                            quickSetupCard
                            advancedCard(currentProfile)
                            customizeCard(currentProfile)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                }
                .navigationTitle("Booking Portal")
                .navigationBarTitleDisplayMode(.inline)
                .alert("Regenerate booking link?", isPresented: $showRegenerateConfirm) {
                    Button("Regenerate", role: .destructive) {
                        Task { await registerNewSlug(force: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your old link may stop working for clients.")
                }
                .alert("Booking Link Error", isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "Something went wrong.")
                }
                .alert("Missing Email", isPresented: $showMissingEmailAlert) {
                    Button("Open Business Profile") {
                        showShare = false
                        showSafari = false
                        showBusinessProfile = true
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Add a business email in Business Profile to receive booking notifications.")
                }
                .sheet(isPresented: $showShare) {
                    if let bookingURL {
                        ShareSheet(items: [bookingURL])
                    }
                }
                .sheet(isPresented: $showBusinessProfile) {
                    NavigationStack {
                        BusinessProfileView()
                            .navigationTitle("Business Profile")
                    }
                }
                .sheet(isPresented: $showSafari) {
                    if let bookingURL {
                        SafariView(url: bookingURL, onDone: { showSafari = false })
                    }
                }
                .overlay(alignment: .bottom) {
                    if showCopyToast {
                        Text(toastMessage)
                            .font(.footnote.weight(.semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(radius: 8, y: 4)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showCopyToast = false
                                    }
                                }
                            }
                    }
                }
            } else {
                ProgressView("Loading…")
                    .navigationTitle("Booking Portal")
            }
        }
        .onAppear {
            loadProfile()
        }
        .task(id: profile?.businessID) {
            await ensureSlugIfNeeded()
        }
    }

    private func hero(_ profile: BusinessProfile) -> some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Client Booking Link")
                            .font(.system(size: 28, weight: .heavy))
                        Text("Share your public booking page")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusChip(
                        text: bookingSlug.isEmpty ? "Not Ready" : "Live",
                        color: bookingSlug.isEmpty ? .orange : SBWTheme.brandGreen,
                        systemImage: "circle.fill"
                    )
                }

                Text(bookingURLString)
                    .font(.footnote)
                    .foregroundStyle(bookingSlug.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Registering link…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if isOwnerEmailMissing {
                    Text("Add a business email to receive booking request notifications.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var actionsCard: some View {
        PremiumPanel {
            DisclosureGroup(isExpanded: $showActions) {
                VStack(spacing: 10) {
                    ActionButtonRow(
                        primaryTitle: "Copy Link",
                        primaryIcon: "doc.on.doc",
                        primaryTint: SBWTheme.brandBlue,
                        primaryDisabled: bookingURL == nil || isGenerating,
                        secondaryTitle: "Share",
                        secondaryIcon: "square.and.arrow.up",
                        secondaryDisabled: bookingURL == nil || isGenerating
                    ) {
                        guard let bookingURL else { return }
                        UIPasteboard.general.string = bookingURL.absoluteString
                        toastMessage = "Copied to clipboard"
                        showCopyToast = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } secondaryAction: {
                        showSafari = false
                        showBusinessProfile = false
                        showShare = true
                    }

                    Button {
                        showShare = false
                        showBusinessProfile = false
                        showSafari = true
                    } label: {
                        Label("View as Client", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(bookingURL == nil || isGenerating || isOwnerEmailMissing)
                }
                .padding(.top, 8)
            } label: {
                SectionTitle(title: "Actions", subtitle: "Share and test your link", icon: "paperplane.circle")
            }
            .tint(.secondary)
        }
    }

    private var quickSetupCard: some View {
        PremiumPanel {
            DisclosureGroup(isExpanded: $showQuickSetup) {
                VStack(spacing: 10) {
                    metricRow("Services", value: servicesSummaryText)
                    metricRow("Business Hours", value: hoursSummaryText)
                    metricRow("Default appointment", value: defaultAppointmentText)

                    Button {
                        Task { await syncBookingSettingsNow() }
                    } label: {
                        if isSyncingSettings {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Syncing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncingSettings)

                    if let lastSyncedAt {
                        Text("Synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionTitle(title: "Quick Setup", subtitle: "Portal readiness", icon: "checklist")
            }
            .tint(.secondary)
        }
    }

    private func advancedCard(_ currentProfile: BusinessProfile) -> some View {
        PremiumPanel {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: 10) {
                    HStack {
                        Text("Link ending")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(bookingSlug.isEmpty ? "(Not set)" : bookingSlug)
                            .font(.footnote)
                            .foregroundStyle(bookingSlug.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }

                    if bookingSlug.isEmpty {
                        Button("Create my booking link") {
                            Task { await registerNewSlug(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating)
                    } else {
                        Button("Change booking link address…") {
                            Task { await registerNewSlug(force: true) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)

                        Button("Regenerate link", role: .destructive) {
                            showRegenerateConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)
                    }

                    if isOwnerEmailMissing {
                        Button("Open Business Profile") {
                            showBusinessProfile = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            } label: {
                SectionTitle(title: "Advanced", subtitle: "Link settings", icon: "slider.horizontal.3")
            }
            .tint(.secondary)
        }
    }

    private func customizeCard(_ currentProfile: BusinessProfile) -> some View {
        PremiumPanel {
            NavigationLink {
                BookingPortalCustomizeView(profile: currentProfile)
            } label: {
                HStack {
                    SectionTitle(title: "Customize Info", subtitle: "Brand, services, hours", icon: "paintpalette")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func loadProfile() {
        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)

            guard let bizID = activeBiz.activeBusinessID else { return }

            if let existing = profiles.first(where: { $0.businessID == bizID }) {
                self.profile = existing
                if existing.bookingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !existing.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.bookingURL = "\(bookingBaseURL)/\(existing.bookingSlug)"
                    try? modelContext.save()
                }
                Task { await syncBookingSlugIfNeeded(profile: existing) }
            } else {
                let created = BusinessProfile(businessID: bizID)
                modelContext.insert(created)
                try? modelContext.save()
                self.profile = created
            }
        } catch {
            self.profile = profiles.first
        }
    }

    private var servicesSummaryText: String {
        guard let profile else { return "No services configured" }
        if let services = decodeServices(from: profile.bookingServicesJSON), !services.isEmpty {
            return "\(services.count) services"
        }
        let fallback = (profile.bookingServicesText ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if fallback.isEmpty { return "No services configured" }
        return "\(fallback.count) services"
    }

    private var defaultAppointmentText: String {
        let minutes = profile?.bookingSlotMinutes ?? 30
        return "\(minutes) minutes"
    }

    private var hoursSummaryText: String {
        guard let profile else { return "Not set" }
        if let summary = summarizeBusinessHours(json: profile.bookingHoursJSON) {
            return summary
        }
        return profile.bookingHoursJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : "Custom"
    }

    private func summarizeBusinessHours(json: String?) -> String? {
        guard let json else { return nil }
        guard let config = PortalHoursConfig.fromJSON(json) else { return nil }

        let weekdays: [PortalWeekday] = [.mon, .tue, .wed, .thu, .fri]
        let dayHours = weekdays.compactMap { hoursString(for: $0, in: config) }
        if dayHours.count == weekdays.count, let first = dayHours.first,
           dayHours.allSatisfy({ $0 == first }) {
            return "Mon–Fri \(first)"
        }

        if let mon = hoursString(for: .mon, in: config) {
            return "Mon \(mon)"
        }

        return nil
    }

    private func hoursString(for day: PortalWeekday, in config: PortalHoursConfig) -> String? {
        guard let dayInfo = config.days[day], dayInfo.isOpen else { return nil }
        guard let start = dayInfo.start, let end = dayInfo.end else { return nil }
        let startTrimmed = start.trimmingCharacters(in: .whitespacesAndNewlines)
        let endTrimmed = end.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !startTrimmed.isEmpty, !endTrimmed.isEmpty else { return nil }
        return "\(startTrimmed)–\(endTrimmed)"
    }

    private func decodeServices(from json: String) -> [BookingServiceOption]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([BookingServiceOption].self, from: data)
    }

    @MainActor
    private func syncBookingSettingsNow() async {
        guard let profile else { return }
        guard let businessId = activeBiz.activeBusinessID else { return }
        guard !isSyncingSettings else { return }

        isSyncingSettings = true
        defer { isSyncingSettings = false }

        let services: [BookingServiceOption]
        if let decoded = decodeServices(from: profile.bookingServicesJSON), !decoded.isEmpty {
            services = decoded
        } else {
            let fallback = (profile.bookingServicesText ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { BookingServiceOption(name: $0, durationMinutes: profile.bookingSlotMinutes) }
            services = fallback
        }

        let hoursConfig = PortalHoursConfig.fromJSON(profile.bookingHoursJSON)

        let settings = BookingSettingsDTO(
            businessId: businessId.uuidString,
            slug: bookingSlug.isEmpty ? nil : bookingSlug,
            brandName: (profile.bookingBrandName ?? profile.name).trimmingCharacters(in: .whitespacesAndNewlines),
            ownerEmail: (profile.bookingOwnerEmail ?? profile.email).trimmingCharacters(in: .whitespacesAndNewlines),
            services: services.isEmpty ? nil : services,
            businessHours: hoursConfig?.toBusinessHoursDict(),
            hoursJson: hoursConfig?.toJSON(),
            slotMinutes: profile.bookingTimeIncrementMinutes,
            bookingSlotMinutes: profile.bookingSlotMinutes,
            minBookingMinutes: profile.bookingMinBookingMinutes,
            maxBookingMinutes: profile.bookingMaxBookingMinutes,
            allowSameDay: profile.bookingAllowSameDay
        )

        do {
            _ = try await PortalBackend.shared.upsertBookingSettings(
                businessId: businessId,
                settings: settings
            )
            let latest = try? await PortalBackend.shared.fetchBookingSettings(businessId: businessId.uuidString)
            if let latest {
                profile.bookingBrandName = latest.brandName ?? profile.bookingBrandName
                profile.bookingOwnerEmail = latest.ownerEmail ?? profile.bookingOwnerEmail
                if let hoursJson = latest.hoursJson {
                    profile.bookingHoursJSON = hoursJson
                }
            }
            if profile.bookingServicesJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let encoded = encodeServices(services) {
                profile.bookingServicesJSON = encoded
                try? modelContext.save()
            }
            lastSyncedAt = Date()
            toastMessage = "Synced"
            showCopyToast = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func encodeServices(_ services: [BookingServiceOption]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(services) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    private func ensureSlugIfNeeded() async {
        guard profile != nil else { return }
        guard bookingSlug.isEmpty else { return }
        guard !isGenerating else { return }
        guard !didAttemptSlug else { return }

        didAttemptSlug = true
        await registerNewSlug(force: true)
    }

    @MainActor
    private func registerNewSlug(force: Bool) async {
        guard let profile else { return }
        if !force && !bookingSlug.isEmpty { return }

        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        defer { isGenerating = false }

        let baseSlug = makeSlug(from: profile.name)
        let trimmedOwner = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOwner.isEmpty {
            showMissingEmailAlert = true
            return
        }

        do {
            let finalSlug = try await registerSlugWithRetry(
                baseSlug: baseSlug,
                businessId: profile.businessID,
                brandName: profile.name,
                ownerEmail: trimmedOwner
            )
            profile.bookingSlug = finalSlug
            profile.bookingURL = "\(bookingBaseURL)/\(finalSlug)"
            try? modelContext.save()
        } catch {
            if error is CancellationError {
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func registerSlugWithRetry(
        baseSlug: String,
        businessId: UUID,
        brandName: String,
        ownerEmail: String?
    ) async throws -> String {
        var lastError: Error?

        let trimmedOwner = ownerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for attempt in 1...10 {
            let candidate = (attempt == 1) ? baseSlug : "\(baseSlug)-\(attempt)"
            do {
                #if DEBUG
                print("[bookinglink] generate start", businessId.uuidString, candidate)
                #endif
                try await PortalBackend.shared.upsertBookingSlug(
                    businessId: businessId,
                    slug: candidate,
                    brandName: brandName,
                    ownerEmail: trimmedOwner
                )
                #if DEBUG
                let link = "\(bookingBaseURL)/\(candidate)"
                print("[bookinglink] generate success", link)
                #endif
                return candidate
            } catch {
                lastError = error
                #if DEBUG
                print("[bookinglink] generate error", error)
                #endif
                if case PortalBackendError.http(let code, _, _) = error, code == 409, attempt < 10 {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? PortalBackendError.http(409, body: "Slug conflict")
    }

    @MainActor
    private func syncBookingSlugIfNeeded(profile: BusinessProfile) async {
        let trimmedSlug = profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSlug.isEmpty else { return }
        let trimmedOwner = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else { return }

        do {
            #if DEBUG
            print("📘 booking slug register attempt", profile.businessID.uuidString, trimmedSlug, trimmedOwner)
            #endif
            try await PortalBackend.shared.upsertBookingSlug(
                businessId: profile.businessID,
                slug: trimmedSlug,
                brandName: profile.name,
                ownerEmail: trimmedOwner
            )
            #if DEBUG
            print("✅ booking slug register success", profile.name, trimmedOwner)
            #endif
        } catch {
            #if DEBUG
            print("❌ booking slug register failed", error.localizedDescription)
            #endif
        }
    }

    private func makeSlug(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        var filtered = ""
        filtered.reserveCapacity(lower.count)

        for ch in lower {
            if ch >= "a" && ch <= "z" {
                filtered.append(ch)
            } else if ch >= "0" && ch <= "9" {
                filtered.append(ch)
            } else if ch == " " || ch == "_" || ch == "-" {
                filtered.append("-")
            }
        }

        var collapsed = ""
        var lastWasHyphen = false
        for ch in filtered {
            if ch == "-" {
                if !lastWasHyphen {
                    collapsed.append(ch)
                }
                lastWasHyphen = true
            } else {
                collapsed.append(ch)
                lastWasHyphen = false
            }
        }

        var slug = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if slug.isEmpty {
            slug = "biz"
        }

        while slug.count < 3 {
            slug += "biz"
        }

        if slug.count > 32 {
            slug = String(slug.prefix(32))
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        if slug.count < 3 {
            slug = "biz"
        }

        return slug
    }

    private var isOwnerEmailMissing: Bool {
        let bookingOwner = profile?.bookingOwnerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profileEmail = profile?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmed = bookingOwner.isEmpty ? profileEmail : bookingOwner
        return trimmed.isEmpty
    }
}

private struct PremiumPanel<Content: View>: View {
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

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: icon)
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

private struct StatusChip: View {
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
    let primaryIcon: String
    let primaryTint: Color
    let primaryDisabled: Bool
    let secondaryTitle: String
    let secondaryIcon: String
    let secondaryDisabled: Bool
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: primaryIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryTint)
            .disabled(primaryDisabled)

            Button(action: secondaryAction) {
                Label(secondaryTitle, systemImage: secondaryIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(secondaryDisabled)
        }
    }
}

#Preview {
    BookingPortalView()
        .environmentObject(ActiveBusinessStore())
}
