//
//  BookingPageView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// The booking page: its link, whether it's taking bookings, and everything
/// clients choose from — on one screen, saved as you go.
///
/// This was two screens (Booking Portal and Customize Info) with a Quick
/// Setup card, a Sync Now button, and an Advanced card whose "Change booking
/// link address" did the same as Regenerate. "Live" only meant a link ending
/// existed on this phone; "Enable Booking Portal" and the instructions said
/// they synced but never left the phone; the brand name and owner email were
/// separate copies of the profile's; and edits only reached the phone after
/// the server accepted them, so offline edits were lost. Now each edit is
/// saved on the phone first and then synced, Live is checked on the server,
/// and the name and email come from the profile.
struct BookingPageView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @State private var services: [BookingServiceOption] = []
    @State private var hours: [BookingHoursRow] = BookingHoursRow.defaults()
    @State private var loaded = false
    @State private var sync: SyncState = .idle
    @State private var syncTask: Task<Void, Never>? = nil
    @State private var liveStatus: PortalBackend.PublicBookingStatus? = nil
    @State private var creatingLink = false
    @State private var linkError: String? = nil
    @State private var showAddressSheet = false
    @State private var showPreview = false
    @State private var copied = false
    /// What was last sent (or found on open), so only real changes sync.
    @State private var lastSent: String? = nil

    enum SyncState: Equatable { case idle, saving, saved, failed }

    private var profile: BusinessProfile? {
        profiles.first { $0.businessID == activeBiz.activeBusinessID }
    }

    var body: some View {
        Group {
            if let profile {
                form(profile)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Booking Page")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Form

    private func form(_ profile: BusinessProfile) -> some View {
        let slug = profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        return Form {
            linkSection(profile, slug: slug)

            if !slug.isEmpty {
                Section {
                    Toggle("Taking bookings", isOn: Binding(
                        get: { profile.bookingEnabled },
                        set: { profile.bookingEnabled = $0; changed(profile) }
                    ))
                } footer: {
                    Text(profile.bookingEnabled
                         ? "Clients can request a time. You confirm each one."
                         : "The page tells clients you're not taking bookings right now.")
                }
            }

            Section {
                ForEach($services) { $service in
                    HStack {
                        TextField("Service", text: $service.name)
                            .onSubmit { changed(profile) }
                        Picker("", selection: $service.durationMinutes) {
                            ForEach(durationChoices(profile), id: \.self) { Text(Self.durationText($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .onDelete { services.remove(atOffsets: $0); changed(profile) }
                Button("Add a Service") {
                    services.append(BookingServiceOption(name: "", durationMinutes: profile.bookingSlotMinutes))
                }
            } header: {
                Text("Services")
            } footer: {
                if services.isEmpty { Text("Add at least one so clients can pick what they need.") }
            }
            .onChange(of: services) { _, _ in changed(profile) }

            Section {
                ForEach($hours) { $row in
                    Toggle(row.day.fullName, isOn: $row.isOpen)
                    if row.isOpen {
                        HStack {
                            DatePicker("Opens", selection: $row.start, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("to").foregroundStyle(.secondary)
                            DatePicker("Closes", selection: $row.end, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Spacer()
                        }
                    }
                }
                Button("Copy Monday to Weekdays") { copyMondayToWeekdays() }
            } header: {
                Text("Hours")
            } footer: {
                Text("Times are in \(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier).")
            }
            .onChange(of: hours) { _, _ in changed(profile) }

            Section("Options") {
                Picker("Time slots every", selection: Binding(
                    get: { profile.bookingTimeIncrementMinutes },
                    set: { profile.bookingTimeIncrementMinutes = $0; roundDurations(to: $0); changed(profile) }
                )) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                Toggle("Same-day bookings", isOn: Binding(
                    get: { profile.bookingAllowSameDay ?? false },
                    set: { profile.bookingAllowSameDay = $0; changed(profile) }
                ))
            }

            Section {
                TextField("Parking, what to bring, how to prepare…", text: Binding(
                    get: { profile.bookingInstructions },
                    set: { profile.bookingInstructions = $0; changed(profile) }
                ), axis: .vertical)
                .lineLimit(3...8)
            } header: {
                Text("Note for Clients")
            } footer: {
                Text("Shown above the booking form.")
            }

            Section {
                syncFooter(profile)
            } footer: {
                Text("Your business name and email come from Profile and Logo.")
            }
        }
        .task { load(profile) }
        .sheet(isPresented: $showAddressSheet) {
            BookingAddressSheet(currentSlug: slug) { newSlug in
                try await changeAddress(to: newSlug, profile: profile)
            }
        }
        .sheet(isPresented: $showPreview) {
            if let url = Self.pageURL(slug: slug) {
                SafariView(url: url) { showPreview = false }
            }
        }
    }

    @ViewBuilder
    private func linkSection(_ profile: BusinessProfile, slug: String) -> some View {
        Section {
            if slug.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Let clients request a time")
                        .font(.headline)
                    Text("You get a link to share. Requests come to Bookings, and you confirm each one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button {
                    Task { await createLink(profile) }
                } label: {
                    HStack {
                        if creatingLink { ProgressView() }
                        Text("Create My Booking Link")
                    }
                }
                .disabled(creatingLink)
                if let linkError {
                    Text(linkError).font(.footnote).foregroundStyle(.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.displayURL(slug: slug))
                            .font(.headline)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        liveBadge(profile)
                    }
                    Text(liveDetail(profile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if let url = Self.pageURL(slug: slug) {
                    ShareLink(item: url) { Label("Share Link", systemImage: "square.and.arrow.up") }
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button { showPreview = true } label: { Label("View as Client", systemImage: "eye") }
                }
                Button { showAddressSheet = true } label: { Label("Change Address", systemImage: "pencil") }
            }
        }
    }

    private func liveBadge(_ profile: BusinessProfile) -> some View {
        let (text, color): (String, Color) = {
            switch liveStatus {
            case .live(let accepting):
                return accepting && profile.bookingEnabled ? ("Live", SBWTheme.success) : ("Paused", .secondary)
            case .notFound: return ("Not live", SBWTheme.attention)
            case .none: return ("Checking…", .secondary)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func liveDetail(_ profile: BusinessProfile) -> String {
        switch liveStatus {
        case .live(let accepting):
            return accepting ? "Clients can open it and request a time." : "Clients see that you're not taking bookings."
        case .notFound: return "The page isn't on the server yet. It's sent with your next change."
        case .none: return "Checking the page…"
        }
    }

    @ViewBuilder
    private func syncFooter(_ profile: BusinessProfile) -> some View {
        switch sync {
        case .idle, .saved:
            Label(sync == .saved ? "Saved" : "Saved as you go", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .saving:
            HStack { ProgressView(); Text("Saving…").foregroundStyle(.secondary) }
        case .failed:
            HStack {
                Label("Saved on this iPhone. Couldn't update the page.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SBWTheme.attention)
                Spacer()
                Button("Retry") { Task { await push(profile) } }
            }
        }
    }

    // MARK: - Load and save

    private func load(_ profile: BusinessProfile) {
        guard !loaded else { return }
        services = BookingPageStore.services(profile)
        if let config = PortalHoursConfig.fromJSON(profile.bookingHoursJSON) {
            hours = BookingHoursRow.from(config: config)
        }
        lastSent = BookingPageStore.signature(profile)
        loaded = true
        Task { await refreshLive(profile) }
    }

    /// Saved on the phone now; sent to the page a moment later.
    private func changed(_ profile: BusinessProfile) {
        guard loaded else { return }
        BookingPageStore.store(services: services, hours: hours, into: profile)
        try? modelContext.save()
        guard BookingPageStore.signature(profile) != lastSent else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await push(profile)
        }
    }

    @MainActor
    private func push(_ profile: BusinessProfile) async {
        guard !profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sync = .saving
        do {
            try await BookingPageStore.push(profile)
            lastSent = BookingPageStore.signature(profile)
            sync = .saved
            await refreshLive(profile)
        } catch {
            sync = .failed
        }
    }

    @MainActor
    private func refreshLive(_ profile: BusinessProfile) async {
        let slug = profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { liveStatus = nil; return }
        liveStatus = try? await PortalBackend.shared.fetchPublicBookingStatus(slug: slug)
    }

    @MainActor
    private func createLink(_ profile: BusinessProfile) async {
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            linkError = "Add your business email in Profile and Logo first. Booking requests are sent there."
            return
        }
        creatingLink = true
        linkError = nil
        defer { creatingLink = false }
        do {
            let slug = try await BookingLink.register(
                base: BookingLink.suggestedSlug(from: profile.name),
                profile: profile
            )
            profile.bookingSlug = slug
            profile.bookingURL = Self.pageURL(slug: slug)?.absoluteString ?? ""
            profile.bookingEnabled = true
            BookingPageStore.store(services: services, hours: hours, into: profile)
            try? modelContext.save()
            await push(profile)
        } catch {
            linkError = "Couldn't create the link. Check your connection and try again."
        }
    }

    @MainActor
    private func changeAddress(to newSlug: String, profile: BusinessProfile) async throws {
        try await BookingLink.claim(slug: newSlug, profile: profile)
        profile.bookingSlug = newSlug
        profile.bookingURL = Self.pageURL(slug: newSlug)?.absoluteString ?? ""
        try? modelContext.save()
        liveStatus = nil
        copied = false
        await push(profile)
    }

    // MARK: - Helpers

    private func durationChoices(_ profile: BusinessProfile) -> [Int] {
        let step = max(15, profile.bookingTimeIncrementMinutes)
        let base = stride(from: step, through: 240, by: step).map { $0 }
        let current = services.map(\.durationMinutes).filter { !base.contains($0) }
        return (base + current).sorted()
    }

    private func roundDurations(to step: Int) {
        for i in services.indices {
            let d = services[i].durationMinutes
            services[i].durationMinutes = max(step, Int((Double(d) / Double(step)).rounded(.up)) * step)
        }
    }

    private func copyMondayToWeekdays() {
        guard let monday = hours.first(where: { $0.day == .mon }) else { return }
        for i in hours.indices where [.tue, .wed, .thu, .fri].contains(hours[i].day) {
            hours[i].isOpen = monday.isOpen
            hours[i].start = monday.start
            hours[i].end = monday.end
        }
    }

    static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static let host = "book.smallbizworkspace.com"
    static func displayURL(slug: String) -> String { "\(host)/\(slug)" }
    static func pageURL(slug: String) -> URL? {
        slug.isEmpty ? nil : URL(string: "https://\(host)/\(slug)")
    }
}

/// Where the booking page's settings live on the phone, and sending them to
/// the page. Name and email are the profile's.
enum BookingPageStore {
    static func services(_ profile: BusinessProfile) -> [BookingServiceOption] {
        if let data = profile.bookingServicesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([BookingServiceOption].self, from: data), !decoded.isEmpty {
            return decoded
        }
        return (profile.bookingServicesText ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BookingServiceOption(name: $0, durationMinutes: profile.bookingSlotMinutes) }
    }

    static func store(services: [BookingServiceOption], hours: [BookingHoursRow], into profile: BusinessProfile) {
        let clean = services
            .map { BookingServiceOption(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), durationMinutes: $0.durationMinutes) }
            .filter { !$0.name.isEmpty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        profile.bookingServicesJSON = (try? encoder.encode(clean)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        profile.bookingServicesText = clean.map(\.name).joined(separator: "\n")
        profile.bookingHoursJSON = BookingHoursRow.toConfig(from: hours)?.toJSON() ?? ""
        if let first = clean.first { profile.bookingSlotMinutes = first.durationMinutes }
    }

    static func settingsDTO(for profile: BusinessProfile) -> BookingSettingsDTO {
        let services = self.services(profile)
        let config = PortalHoursConfig.fromJSON(profile.bookingHoursJSON)
        let slug = profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let durations = services.map(\.durationMinutes)
        return BookingSettingsDTO(
            businessId: profile.businessID.uuidString,
            slug: slug.isEmpty ? nil : slug,
            brandName: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerEmail: profile.email.trimmingCharacters(in: .whitespacesAndNewlines),
            services: services.isEmpty ? nil : services,
            businessHours: config?.toBusinessHoursDict(),
            hoursJson: config?.toJSON(),
            slotMinutes: profile.bookingTimeIncrementMinutes,
            bookingSlotMinutes: durations.min() ?? profile.bookingSlotMinutes,
            minBookingMinutes: durations.min(),
            maxBookingMinutes: durations.max().map { max($0, 240) },
            allowSameDay: profile.bookingAllowSameDay ?? false,
            acceptingBookings: profile.bookingEnabled,
            clientNote: profile.bookingInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The settings as they'd be sent; equal signatures mean nothing to sync.
    static func signature(_ profile: BusinessProfile) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(settingsDTO(for: profile))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func push(_ profile: BusinessProfile) async throws {
        _ = try await PortalBackend.shared.upsertBookingSettings(
            businessId: profile.businessID,
            settings: settingsDTO(for: profile)
        )
    }
}

/// Booking link endings: suggesting, checking and claiming them.
enum BookingLink {
    enum ClaimError: LocalizedError, Equatable {
        case invalid, taken
        var errorDescription: String? {
            switch self {
            case .invalid: return "Use 3 to 32 lowercase letters, numbers or dashes."
            case .taken: return "That address is taken. Try another."
            }
        }
    }

    static func isValid(_ slug: String) -> Bool {
        slug.range(of: "^[a-z0-9-]{3,32}$", options: .regularExpression) != nil
            && !slug.hasPrefix("-") && !slug.hasSuffix("-")
    }

    /// "Dunn's Lawn & Garden" → "dunns-lawn-garden".
    static func suggestedSlug(from name: String) -> String {
        var out = ""
        var lastDash = false
        for ch in name.lowercased() {
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) {
                out.append(ch); lastDash = false
            } else if ch == " " || ch == "-" || ch == "_" || ch == "&" || ch == "/" {
                if !lastDash, !out.isEmpty { out.append("-"); lastDash = true }
            }
        }
        var slug = String(out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(32))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "book" }
        while slug.count < 3 { slug += "-biz" }
        return slug
    }

    /// Normalizes what the owner typed: lowercase, spaces to dashes.
    static func normalized(_ typed: String) -> String {
        typed.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    /// Claims `slug` for this business, or throws `.taken`.
    static func claim(slug: String, profile: BusinessProfile) async throws {
        guard isValid(slug) else { throw ClaimError.invalid }
        do {
            try await PortalBackend.shared.upsertBookingSlug(
                businessId: profile.businessID,
                slug: slug,
                brandName: profile.name,
                ownerEmail: profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch PortalBackendError.http(409, _, _) {
            throw ClaimError.taken
        }
    }

    /// Claims `base`, or `base-2`, `base-3`… if it's taken.
    static func register(base: String, profile: BusinessProfile) async throws -> String {
        for attempt in 1...10 {
            let candidate = attempt == 1 ? base : String(base.prefix(29)) + "-\(attempt)"
            do {
                try await claim(slug: candidate, profile: profile)
                return candidate
            } catch ClaimError.taken {
                continue
            }
        }
        throw ClaimError.taken
    }
}

/// Typing a new link ending.
private struct BookingAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentSlug: String
    let onSave: (String) async throws -> Void

    @State private var typed = ""
    @State private var error: String? = nil
    @State private var saving = false

    private var candidate: String { BookingLink.normalized(typed) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Text("\(BookingPageView.host)/")
                            .foregroundStyle(.secondary)
                        TextField("your-business", text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: typed) { _, _ in error = nil }
                    }
                    .font(.callout)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Lowercase letters, numbers and dashes. The old link keeps working, so links you've already shared don't break.")
                    }
                }
            }
            .navigationTitle("Booking Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(candidate.isEmpty || candidate == currentSlug)
                    }
                }
            }
            .onAppear { typed = currentSlug }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard BookingLink.isValid(candidate) else {
            error = BookingLink.ClaimError.invalid.errorDescription
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await onSave(candidate)
            dismiss()
        } catch let claim as BookingLink.ClaimError {
            error = claim.errorDescription
        } catch {
            self.error = "Couldn't change the address. Check your connection and try again."
        }
    }
}

/// One day's opening hours in the editor.
struct BookingHoursRow: Identifiable, Equatable {
    let day: PortalWeekday
    var isOpen: Bool
    var start: Date
    var end: Date

    var id: String { day.rawValue }

    static func defaults() -> [BookingHoursRow] {
        PortalWeekday.allCases.map {
            BookingHoursRow(day: $0, isOpen: false, start: time(9, 0), end: time(17, 0))
        }
    }

    static func from(config: PortalHoursConfig) -> [BookingHoursRow] {
        PortalWeekday.allCases.map { day in
            let info = config.days[day] ?? PortalHoursDay(isOpen: false, start: nil, end: nil)
            return BookingHoursRow(
                day: day,
                isOpen: info.isOpen,
                start: parse(info.start) ?? time(9, 0),
                end: parse(info.end) ?? time(17, 0)
            )
        }
    }

    static func toConfig(from rows: [BookingHoursRow]) -> PortalHoursConfig? {
        guard !rows.isEmpty else { return nil }
        var map: [PortalWeekday: PortalHoursDay] = [:]
        for row in rows {
            map[row.day] = PortalHoursDay(
                isOpen: row.isOpen,
                start: row.isOpen ? format(row.start) : nil,
                end: row.isOpen ? format(row.end) : nil
            )
        }
        return PortalHoursConfig(days: map)
    }

    static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    static func format(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return time(parts[0], parts[1])
    }
}

extension PortalWeekday {
    var fullName: String {
        switch self {
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }
}

extension BookingPageView: Equatable {
    static func == (_: BookingPageView, _: BookingPageView) -> Bool { true }
}
