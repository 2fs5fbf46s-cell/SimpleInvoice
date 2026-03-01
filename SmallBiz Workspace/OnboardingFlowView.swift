import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UserNotifications

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var businesses: [Business]
    @Query private var profiles: [BusinessProfile]

    @State private var step: Int = 0
    @State private var businessName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var addressLine1: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var logoData: Data?
    @State private var didPrefillExistingData = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                SBWTheme.headerWash()

                ScrollView {
                    VStack(spacing: 12) {
                        SBWCardContainer {
                            currentStepContent
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Getting Started")
                        .font(.headline)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .task {
                prefillFromExistingBusinessIfNeeded()
            }
            .onChange(of: selectedLogoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    await MainActor.run {
                        logoData = data
                    }
                }
            }
            .alert("Setup Issue", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        ZStack {
            if step == 0 {
                welcomeStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else if step == 1 {
                businessStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                notificationsStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            iconChip(systemName: "sparkles")

            Text("Welcome to SmallBiz Workspace")
                .font(.title3.weight(.bold))

            Text("Let’s set up your business in under 2 minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "building.2", title: "Business setup", subtitle: "Add your business details")
                featureRow(icon: "bell.badge", title: "Notifications", subtitle: "Get paid and booking alerts")
                featureRow(icon: "creditcard", title: "Payments later", subtitle: "Connect providers when ready")
            }
            .padding(.top, 4)
        }
    }

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            iconChip(systemName: "building.2")

            Text("Business Setup")
                .font(.title3.weight(.bold))

            Text("Add your details so invoices and customer views are prefilled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().overlay(Color.white.opacity(0.08))

            labeledField("Business Name") {
                TextField("My Business", text: $businessName)
                    .textInputAutocapitalization(.words)
            }

            labeledField("Email (optional)") {
                TextField("name@company.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            labeledField("Phone (optional)") {
                TextField("(555) 123-4567", text: $phone)
                    .keyboardType(.phonePad)
            }

            labeledField("Address (optional)") {
                VStack(spacing: 8) {
                    TextField("Street", text: $addressLine1)
                    HStack(spacing: 8) {
                        TextField("City", text: $city)
                        TextField("State", text: $state)
                        TextField("ZIP", text: $zip)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                Text("Logo (optional)")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                        if let logoData,
                           let image = UIImage(data: logoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )

                    PhotosPicker(selection: $selectedLogoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose Logo", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            iconChip(systemName: "bell.badge")

            Text("Turn on notifications?")
                .font(.title3.weight(.bold))

            Text("Stay on top of payments and customer activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "checkmark.circle", title: "Invoice paid alerts", subtitle: "Know when money comes in")
                featureRow(icon: "checkmark.circle", title: "Booking alerts", subtitle: "Respond quickly to new requests")
                featureRow(icon: "checkmark.circle", title: "Due reminders", subtitle: "Keep important items on track")
            }
            .padding(.top, 4)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if step == 0 {
                Button("Skip for now") {
                    Haptics.lightTap()
                    Task { await skipFlowTapped() }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Button {
                    Haptics.lightTap()
                    withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            } else if step == 1 {
                Button("Back") {
                    Haptics.lightTap()
                    withAnimation(.easeInOut(duration: 0.2)) { step = 0 }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Button {
                    Haptics.lightTap()
                    Task { await saveBusinessAndContinueTapped() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save & Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(trimmedBusinessName.isEmpty || isSaving)
            } else {
                Button("Not Now") {
                    Haptics.lightTap()
                    Task { await finishOnboarding(notificationsChoice: "not_now", didRequestNotifications: false) }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Button {
                    Haptics.lightTap()
                    Task { await enableNotificationsTapped() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Enable Notifications")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )
    }

    private var trimmedBusinessName: String {
        businessName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var assembledAddress: String {
        let line = addressLine1.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityPart = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let statePart = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let zipPart = zip.trimmingCharacters(in: .whitespacesAndNewlines)

        var locality = cityPart
        if !statePart.isEmpty {
            locality = locality.isEmpty ? statePart : "\(locality), \(statePart)"
        }
        if !zipPart.isEmpty {
            locality = locality.isEmpty ? zipPart : "\(locality) \(zipPart)"
        }

        if line.isEmpty { return locality }
        if locality.isEmpty { return line }
        return "\(line), \(locality)"
    }

    @MainActor
    private func prefillFromExistingBusinessIfNeeded() {
        guard !didPrefillExistingData else { return }
        didPrefillExistingData = true

        let sourceBusiness: Business? = {
            if let active = activeBiz.activeBusinessID {
                return businesses.first(where: { $0.id == active })
            }
            return businesses.first
        }()

        if trimmedBusinessName.isEmpty {
            businessName = sourceBusiness?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let sourceProfile: BusinessProfile? = {
            if let businessID = sourceBusiness?.id {
                return profiles.first(where: { $0.businessID == businessID })
            }
            return nil
        }()

        guard let sourceProfile else { return }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { email = sourceProfile.email }
        if phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { phone = sourceProfile.phone }
        if addressLine1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addressLine1 = sourceProfile.address }
        if logoData == nil { logoData = sourceProfile.logoData }
    }

    @MainActor
    private func skipFlowTapped() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if trimmedBusinessName.isEmpty {
                businessName = "My Business"
            }
            try persistOnboarding()
            await finishOnboarding(notificationsChoice: "not_now", didRequestNotifications: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveBusinessAndContinueTapped() async {
        guard !trimmedBusinessName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try persistOnboarding()
            withAnimation(.easeInOut(duration: 0.2)) {
                step = 2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func enableNotificationsTapped() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            UIApplication.shared.registerForRemoteNotifications()
            await finishOnboarding(notificationsChoice: "enabled", didRequestNotifications: true)
        } catch {
            await finishOnboarding(notificationsChoice: "enabled", didRequestNotifications: true)
        }
    }

    @MainActor
    private func finishOnboarding(notificationsChoice: String, didRequestNotifications: Bool) async {
        OnboardingState.setNotificationsChoice(notificationsChoice, didRequest: didRequestNotifications)
        OnboardingState.markComplete()
        if let activeID = activeBiz.activeBusinessID {
            await LocalReminderScheduler.shared.refreshReminders(
                modelContext: modelContext,
                activeBusinessID: activeID
            )
        }
        Haptics.success()
    }

    @MainActor
    private func persistOnboarding() throws {
        let targetBusiness: Business = {
            if let activeID = activeBiz.activeBusinessID,
               let existing = businesses.first(where: { $0.id == activeID }) {
                return existing
            }
            if let first = businesses.first {
                return first
            }
            let created = Business(name: trimmedBusinessName.isEmpty ? "My Business" : trimmedBusinessName, isActive: true)
            modelContext.insert(created)
            return created
        }()

        let finalName = trimmedBusinessName.isEmpty ? "My Business" : trimmedBusinessName
        targetBusiness.name = finalName
        targetBusiness.isActive = true

        let profile: BusinessProfile = {
            if let existing = profiles.first(where: { $0.businessID == targetBusiness.id }) {
                return existing
            }
            let created = BusinessProfile(businessID: targetBusiness.id)
            modelContext.insert(created)
            return created
        }()

        profile.name = finalName
        profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.address = assembledAddress
        if let logoData {
            profile.logoData = logoData
        }

        try modelContext.save()
        activeBiz.setActiveBusiness(targetBusiness.id)
    }

    private func iconChip(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SBWTheme.brandGradient.opacity(0.18))
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 42, height: 42)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(SBWTheme.brandBlue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SBWTheme.cardStroke, lineWidth: 1)
                )
        }
    }
}
