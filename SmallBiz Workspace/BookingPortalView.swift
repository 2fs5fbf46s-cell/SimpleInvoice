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
    @State private var showErrorAlert = false

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
            if let profile {
                Form {
                    Section("Booking Link") {
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

                    }

                    Section("Actions") {
                        Button {
                            guard let bookingURL else { return }
                            UIPasteboard.general.string = bookingURL.absoluteString
                            showCopyToast = true
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }
                        .disabled(bookingURL == nil || isGenerating)

                        Button {
                            showShare = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(bookingURL == nil || isGenerating)

                        Button {
                            showSafari = true
                        } label: {
                            Label("View as Client", systemImage: "safari")
                        }
                        .disabled(bookingURL == nil || isGenerating)
                    }

                    Section("Slug") {
                        Text(bookingSlug.isEmpty ? "(Not set)" : bookingSlug)
                            .font(.footnote)
                            .foregroundStyle(bookingSlug.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)

                        Button {
                            if bookingSlug.isEmpty {
                                Task { await registerNewSlug(force: true) }
                            } else {
                                showRegenerateConfirm = true
                            }
                        } label: {
                            Label(bookingSlug.isEmpty ? "Generate" : "Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isGenerating)
                    }

                    Section {
                        NavigationLink("Customize Info") {
                            BookingPortalCustomizeView(profile: profile)
                        }
                    }
                }
                .navigationTitle("Booking Portal")
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
                .sheet(isPresented: $showShare) {
                    if let bookingURL {
                        ShareSheet(items: [bookingURL])
                    }
                }
                .sheet(isPresented: $showSafari) {
                    if let bookingURL {
                        SafariView(url: bookingURL, onDone: { showSafari = false })
                    }
                }
                .overlay(alignment: .bottom) {
                    if showCopyToast {
                        Text("Copied to clipboard")
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

    private func loadProfile() {
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
        } catch {
            self.profile = profiles.first
        }
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

        do {
            let finalSlug = try await registerSlugWithRetry(
                baseSlug: baseSlug,
                businessId: profile.businessID,
                brandName: profile.name,
                businessEmail: profile.email
            )
            profile.bookingSlug = finalSlug
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
        businessEmail: String?
    ) async throws -> String {
        var lastError: Error?

        for attempt in 1...10 {
            let candidate = (attempt == 1) ? baseSlug : "\(baseSlug)-\(attempt)"
            do {
                print("[bookinglink] generate start", businessId.uuidString, candidate)
                try await PortalBackend.shared.registerBookingSlug(
                    businessId: businessId,
                    slug: candidate,
                    brandName: brandName,
                    businessEmail: businessEmail
                )
                print("[bookinglink] generate success", "\(bookingBaseURL)/\(candidate)")
                return candidate
            } catch {
                lastError = error
                print("[bookinglink] generate error", error)
                if case PortalBackendError.http(let code, _) = error, code == 409, attempt < 10 {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? PortalBackendError.http(409, body: "Slug conflict")
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
}

#Preview {
    BookingPortalView()
        .environmentObject(ActiveBusinessStore())
}
