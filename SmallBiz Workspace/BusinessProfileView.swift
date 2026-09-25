import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// The business's name, contact details, logo and brand color: what prints
/// on invoices, estimates and contracts and what its clients see online.
///
/// This screen used to also hold a payments card (with Stripe and PayPal
/// checks run on every open), notification permission, a second business
/// switcher, invoice numbering, and a "Debug / Metadata" card shown to
/// everyone. Those live in their own rows on the Business sheet now (the
/// debug details in the developer section of debug builds); this is only the
/// profile.
struct BusinessProfileView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var name = ""
    @State private var loadedName = ""
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var brandSyncTask: Task<Void, Never>?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, email, phone, address }

    private var businessID: UUID? { activeBiz.activeBusinessID }
    private var profile: BusinessProfile? {
        profiles.first { $0.businessID == businessID }
    }
    private var business: Business? {
        businesses.first { $0.id == businessID }
    }

    var body: some View {
        Group {
            if let profile {
                form(profile)
            } else {
                ProgressView()
                    .task { ensureProfile() }
            }
        }
        .navigationTitle("Profile and Brand")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { commitName() }
    }

    private func form(_ profile: BusinessProfile) -> some View {
        Form {
            Section {
                logoRow(profile)
            } footer: {
                Text("Goes at the top of invoices, estimates and contracts.")
            }

            brandSection(profile)

            Section {
                TextField("Business name", text: $name)
                    .textContentType(.organizationName)
                    .focused($focused, equals: .name)
                    .submitLabel(.done)
                    .onSubmit(commitName)
                TextField("Email", text: Bindable(profile).email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focused, equals: .email)
                TextField("Phone", text: Bindable(profile).phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focused, equals: .phone)
                TextField("Address", text: Bindable(profile).address, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...5)
                    .focused($focused, equals: .address)
            } header: {
                Text("Business")
            } footer: {
                Text(emailFooter(profile))
            }
        }
        .onAppear {
            name = profile.name
            loadedName = profile.name
        }
        .onChange(of: focused) { old, _ in
            if old == .name { commitName() }
            try? modelContext.save()
        }
        .onChange(of: profile.email) { _, _ in
            // One email everywhere: booking requests go to the profile's.
            profile.bookingOwnerEmail = nil
        }
        .onChange(of: selectedLogoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                profile.logoData = data
                try? modelContext.save()
                BusinessBrandSync.markChanged(profile, context: modelContext)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    private func logoRow(_ profile: BusinessProfile) -> some View {
        HStack(spacing: 14) {
            Group {
                if let data = profile.logoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(BusinessIdentity.initials(for: name))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BrandColor.color(BrandColor.readableOnWhite(BrandColor.resolved(profile.brandColorHex))))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $selectedLogoItem, matching: .images, photoLibrary: .shared()) {
                    Text(profile.logoData == nil ? "Add Logo" : "Change Logo")
                }
                if profile.logoData != nil {
                    Button("Remove Logo", role: .destructive) {
                        profile.logoData = nil
                        selectedLogoItem = nil
                        try? modelContext.save()
                        BusinessBrandSync.markChanged(profile, context: modelContext)
                    }
                }
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Brand color

    private func brandSection(_ profile: BusinessProfile) -> some View {
        let current = BrandColor.resolved(profile.brandColorHex)
        let logoColor = profile.logoData.flatMap(BrandColor.fromLogo)
        return Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
                ForEach(BrandColor.presets, id: \.hex) { preset in
                    Button { setBrand(preset.hex, profile) } label: {
                        Circle()
                            .fill(BrandColor.color(preset.hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.primary, lineWidth: current == preset.hex ? 2.5 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(current == preset.hex ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)

            if let logoColor {
                Button { setBrand(logoColor, profile) } label: {
                    HStack {
                        Label("Match My Logo", systemImage: "eyedropper")
                        Spacer()
                        Circle().fill(BrandColor.color(logoColor)).frame(width: 20, height: 20)
                    }
                }
            }

            ColorPicker("Custom Color", selection: Binding(
                get: { BrandColor.color(current) },
                set: { setBrand(BrandColor.hex(from: $0), profile) }
            ), supportsOpacity: false)

            brandPreview(current, name: name)
        } header: {
            Text("Brand Color")
        } footer: {
            Text(BrandColor.needsDarkening(current)
                 ? "Clients see this on your invoices, portal, booking page, website and emails. Buttons use a slightly darker shade so white text stays readable."
                 : "Clients see this on your invoices, portal, booking page, website and emails.")
        }
    }

    /// Roughly what a client sees: the header and a Pay button.
    private func brandPreview(_ hex: String, name: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(BusinessIdentity.initials(for: name))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandColor.color(hex))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                Text(name.isEmpty ? "Your business" : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(10)
            .background(BrandColor.color(BrandColor.readableOnWhite(hex)))
            HStack {
                Text("Invoice total $1,200.00").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Pay now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(BrandColor.color(BrandColor.readableOnWhite(hex))))
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SBWTheme.cardStroke))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        .accessibilityLabel("Preview of what clients see")
    }

    private func setBrand(_ hex: String, _ profile: BusinessProfile) {
        guard let normalized = BrandColor.normalize(hex), normalized != profile.brandColorHex else { return }
        profile.brandColorHex = normalized
        try? modelContext.save()
        brandSyncTask?.cancel()
        // The custom picker fires on every drag step; send once it settles.
        brandSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            BusinessBrandSync.markChanged(profile, context: modelContext)
        }
    }

    private func emailFooter(_ profile: BusinessProfile) -> String {
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty { return "Clients reply to this email, and booking requests are sent to it." }
        if !email.contains("@") { return "That email doesn't look right." }
        return "Clients reply to \(email), and booking requests are sent there."
    }

    /// Renames through BusinessIdentity so the switcher, booking page and
    /// website keep the same name.
    private func commitName() {
        guard let profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != loadedName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        BusinessIdentity.rename(profile: profile, business: business, to: trimmed, context: modelContext)
        loadedName = trimmed
    }

    private func ensureProfile() {
        try? activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        guard let businessID, profiles.first(where: { $0.businessID == businessID }) == nil else { return }
        modelContext.insert(BusinessProfile(businessID: businessID))
        try? modelContext.save()
    }
}

/// How invoice numbers look and what the next one will be. Moved out of the
/// profile's Advanced section.
struct InvoiceNumbersView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]
    @State private var confirmReset = false

    private var profile: BusinessProfile? {
        profiles.first { $0.businessID == activeBiz.activeBusinessID }
    }

    var body: some View {
        Form {
            if let profile {
                Section {
                    TextField("Prefix", text: Bindable(profile).invoicePrefix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    LabeledContent("Next invoice", value: InvoiceNumberGenerator.peekNextNumber(profile: profile))
                } footer: {
                    Text("Numbers restart at 001 each January. The prefix is what comes before the year.")
                }
                Section {
                    Button("Start Over at 001", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Only if you're starting fresh. Two invoices can end up with the same number.")
                }
            }
        }
        .navigationTitle("Invoice Numbers")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? modelContext.save() }
        .confirmationDialog("Start invoice numbers over at 001?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Start Over", role: .destructive) {
                profile?.nextInvoiceNumber = 1
                profile?.lastInvoiceYear = Calendar.current.component(.year, from: .now)
                try? modelContext.save()
            }
        }
    }
}

// Pushed onto a NavigationStack; compare by identity so it can't re-render in
// a loop (see InvoiceDetailView's Equatable conformance).
extension BusinessProfileView: Equatable {
    static func == (_: BusinessProfileView, _: BusinessProfileView) -> Bool { true }
}

extension InvoiceNumbersView: Equatable {
    static func == (_: InvoiceNumbersView, _: InvoiceNumbersView) -> Bool { true }
}
