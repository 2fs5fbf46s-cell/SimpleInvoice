import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// The business's name, contact details and logo: what prints on invoices,
/// estimates and contracts and shows on the booking page.
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
        .navigationTitle("Profile and Logo")
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
                        .background(SBWTheme.brandGradient)
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
                    }
                }
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
