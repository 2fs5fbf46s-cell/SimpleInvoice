import SwiftUI
import SwiftData

struct BookingPortalCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: BusinessProfile
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var isInitializing = true
    @State private var isRefreshing = false
    @State private var lastSyncedAt: Date? = nil

    @State private var brandName: String = ""
    @State private var ownerEmail: String = ""
    @State private var services: [BookingServiceOption] = []
    @State private var newServiceName: String = ""
    @State private var newServiceDuration: Int = 30
    @State private var hours: [HoursRow] = HoursRow.defaults()
    @State private var defaultAppointmentMinutes: Int = 30
    @State private var timeIncrementMinutes: Int = 30
    @State private var minBookingMinutesText: String = ""
    @State private var maxBookingMinutesText: String = ""
    @State private var allowSameDay: Bool = false
    @State private var showDurationAdjustedAlert = false
    @State private var defaultDurationAdjustedNote: String? = nil
    @State private var showSyncedToast = false

    var body: some View {
        configuredContent
    }

    private var configuredContent: some View {
        contentView
            .navigationTitle("Customize Info")
            .toolbar { toolbarContent }
            .modifier(changeHandlers)
            .modifier(loadAndRefreshHandler)
            .overlay(alignment: .bottom) {
                if showSyncedToast {
                    Text("Synced just now")
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
                                    showSyncedToast = false
                                }
                            }
                        }
                }
            }
            .alert("Booking Settings Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .alert("Updated Durations", isPresented: $showDurationAdjustedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Adjusted service durations to match your time increments.")
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") {
                Task {
                    let ok = await saveSettings(showErrors: true, showSyncedBanner: true)
                    if ok { dismiss() }
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSaving { ProgressView() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await refreshFromPortal() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
    }

    private var changeHandlers: some ViewModifier {
        ChangeHandlers(
            bookingEnabled: profile.bookingEnabled,
            bookingHoursText: profile.bookingHoursText,
            bookingInstructions: profile.bookingInstructions,
            brandName: brandName,
            ownerEmail: ownerEmail,
            services: services,
            hours: hours,
            defaultAppointmentMinutes: defaultAppointmentMinutes,
            timeIncrementMinutes: timeIncrementMinutes,
            minBookingMinutesText: minBookingMinutesText,
            maxBookingMinutesText: maxBookingMinutesText,
            allowSameDay: allowSameDay
        ) {
            try? modelContext.save()
        } autosave: {
            scheduleAutoSave()
        }
    }

    private var loadAndRefreshHandler: some ViewModifier {
        LoadAndRefreshHandler(onLoad: {
            loadCachedSettings()
        }, onRefresh: {
            await refreshFromPortal()
        })
    }

    private var contentView: some View {
        Form {
            loadingSection
            refreshingSection
            bookingPortalSection
            brandSection
            servicesSection
            businessHoursSection
            bookingOptionsSection
            businessHoursNotesSection
            bookingInstructionsSection
            lastSyncedSection
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if isLoading {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading settings…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var refreshingSection: some View {
        if isRefreshing {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Refreshing from portal…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bookingPortalSection: some View {
        Section("Booking Portal") {
            Toggle("Enable Booking Portal", isOn: Bindable(profile).bookingEnabled)

            Text("These details are saved locally and will appear on your booking page in a future update.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var brandSection: some View {
        Section("Brand") {
            TextField("Brand Name", text: $brandName)
            TextField("Owner Email", text: $ownerEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
        }
    }

    private var servicesSection: some View {
        Section {
            HStack {
                Text("Services / Products")
                Spacer()
                EditButton()
            }

            if services.isEmpty {
                Text("No services configured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($services) { $service in
                    HStack {
                        TextField("Service name", text: $service.name)
                        Spacer()
                        Picker("Duration", selection: $service.durationMinutes) {
                            ForEach(serviceDurationOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .onDelete(perform: deleteServices)
                .onMove(perform: moveServices)
            }

            HStack(spacing: 8) {
                TextField("Add a service", text: $newServiceName)
                    .onSubmit { addService() }
                Picker("Duration", selection: $newServiceDuration) {
                    ForEach(serviceDurationOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                Button("+ Add Service") { addService() }
                    .disabled(newServiceName.trimmed.isEmpty)
            }
        }
    }

    private var businessHoursSection: some View {
        Section("Business Hours") {
            Button("Apply weekday hours to all weekdays") {
                applyWeekdayHours()
            }

            ForEach($hours) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("\(row.day.displayName)", isOn: $row.isOpen)
                    }

                    if row.isOpen {
                        HStack {
                            DatePicker("Open", selection: $row.start, displayedComponents: .hourAndMinute)
                            DatePicker("Close", selection: $row.end, displayedComponents: .hourAndMinute)
                        }
                        .datePickerStyle(.compact)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var bookingOptionsSection: some View {
        Section("Booking Options") {
            Picker("Time increments", selection: $timeIncrementMinutes) {
                ForEach(timeIncrementOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.segmented)

            Text("Service durations must match the increments.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Default appointment length", selection: $defaultAppointmentMinutes) {
                ForEach(defaultDurationOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.menu)

            if let note = defaultDurationAdjustedNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("Minimum booking minutes", text: $minBookingMinutesText)
                .keyboardType(.numberPad)
            TextField("Maximum booking minutes", text: $maxBookingMinutesText)
                .keyboardType(.numberPad)
            Toggle("Allow Same-Day Booking", isOn: $allowSameDay)
        }
    }

    private var businessHoursNotesSection: some View {
        Section("Business Hours (Notes)") {
            TextEditor(text: Bindable(profile).bookingHoursText)
                .frame(minHeight: 140)
                .font(.body)

            Text("Example: Mon: 9am-5pm\nTue: 9am-5pm")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var bookingInstructionsSection: some View {
        Section("Booking Instructions") {
            TextEditor(text: Bindable(profile).bookingInstructions)
                .frame(minHeight: 120)
                .font(.body)
        }
    }

    @ViewBuilder
    private var lastSyncedSection: some View {
        if let lastSyncedAt {
            Section {
                Text("Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func loadCachedSettings() {
        brandName = profile.bookingBrandName ?? profile.name
        ownerEmail = profile.bookingOwnerEmail ?? profile.email
        if let decoded = decodeServices(from: profile.bookingServicesJSON) {
            services = decoded
        } else {
            let fallback = (profile.bookingServicesText ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { BookingServiceOption(name: $0, durationMinutes: profile.bookingSlotMinutes) }
            services = fallback
        }

        if let config = PortalHoursConfig.fromJSON(profile.bookingHoursJSON) {
            hours = HoursRow.from(config: config)
        } else {
            hours = HoursRow.defaults()
        }

        defaultAppointmentMinutes = profile.bookingSlotMinutes
        timeIncrementMinutes = profile.bookingTimeIncrementMinutes
        newServiceDuration = profile.bookingSlotMinutes
        minBookingMinutesText = profile.bookingMinBookingMinutes.map(String.init) ?? ""
        maxBookingMinutesText = profile.bookingMaxBookingMinutes.map(String.init) ?? ""
        allowSameDay = profile.bookingAllowSameDay ?? false
    }

    @MainActor
    private func fetchSettings() async -> Bool {
        guard let businessId = activeBiz.activeBusinessID else { return false }
        guard !isLoading else { return false }

        isLoading = true
        defer {
            isLoading = false
            isInitializing = false
        }

        do {
            let dto = try await PortalBackend.shared.fetchBookingSettings(businessId: businessId)
            if let name = dto.brandName { brandName = name }
            if let email = dto.ownerEmail { ownerEmail = email }
            if let services = dto.services { self.services = services }
            if let hoursJson = dto.hoursJson, let config = PortalHoursConfig.fromJSON(hoursJson) {
                hours = HoursRow.from(config: config)
            } else if let hoursDict = dto.businessHours {
                let config = PortalHoursConfig.fromBusinessHoursDict(hoursDict)
                hours = HoursRow.from(config: config)
            }
            if let slot = dto.bookingSlotMinutes ?? dto.slotMinutes { defaultAppointmentMinutes = slot }
            if let increment = dto.slotMinutes { timeIncrementMinutes = increment }
            if let min = dto.minBookingMinutes { minBookingMinutesText = String(min) }
            if let max = dto.maxBookingMinutes { maxBookingMinutesText = String(max) }
            if let allow = dto.allowSameDay { allowSameDay = allow }

            profile.bookingBrandName = brandName
            profile.bookingOwnerEmail = ownerEmail
            profile.bookingServicesText = services.map { $0.name }.joined(separator: "\n")
            profile.bookingServicesJSON = encodeServices(services) ?? ""
            profile.bookingHoursJSON = HoursRow.toConfig(from: hours)?.toJSON() ?? ""
            profile.bookingSlotMinutes = defaultAppointmentMinutes
            profile.bookingTimeIncrementMinutes = timeIncrementMinutes
            profile.bookingMinBookingMinutes = parseInt(minBookingMinutesText)
            profile.bookingMaxBookingMinutes = parseInt(maxBookingMinutesText)
            profile.bookingAllowSameDay = allowSameDay
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            return false
        }

        return true
    }

    @MainActor
    private func refreshFromPortal() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let ok = await fetchSettings()
        if ok {
            lastSyncedAt = Date()
            showSyncedNotice()
        }
    }

    @MainActor
    private func saveSettings(showErrors: Bool, showSyncedBanner: Bool = false) async -> Bool {
        guard let businessId = activeBiz.activeBusinessID else { return false }
        guard !isSaving else { return false }

        let min = parseInt(minBookingMinutesText)
        let max = parseInt(maxBookingMinutesText)

        if (minBookingMinutesText.trimmed.isEmpty == false && min == nil) ||
            (maxBookingMinutesText.trimmed.isEmpty == false && max == nil) {
            if showErrors {
                errorMessage = "Min/max minutes must be whole numbers."
                showErrorAlert = true
            }
            return false
        }

        let roundedDefault = roundedUpToIncrement(defaultAppointmentMinutes, increment: timeIncrementMinutes)
        if roundedDefault != defaultAppointmentMinutes {
            defaultAppointmentMinutes = roundedDefault
            defaultDurationAdjustedNote = "Adjusted to \(roundedDefault) min to match time increments."
        } else {
            defaultDurationAdjustedNote = nil
        }

        var didAdjustServices = false
        let servicesList = services
            .map { BookingServiceOption(name: $0.name.trimmed, durationMinutes: $0.durationMinutes) }
            .filter { !$0.name.isEmpty }
            .map { option in
                let rounded = roundedUpToIncrement(option.durationMinutes, increment: timeIncrementMinutes)
                if rounded != option.durationMinutes { didAdjustServices = true }
                return BookingServiceOption(name: option.name, durationMinutes: rounded)
            }

        if didAdjustServices {
            services = servicesList
            showDurationAdjustedAlert = true
        }

        let hoursConfig = HoursRow.toConfig(from: hours)
        let hoursJson = hoursConfig?.toJSON()
        let hoursDict = hoursConfig?.toBusinessHoursDict()

        let trimmedSlug = profile.bookingSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = BookingSettingsDTO(
            businessId: businessId.uuidString,
            slug: trimmedSlug.isEmpty ? nil : trimmedSlug,
            brandName: brandName.trimmedOrNil,
            ownerEmail: ownerEmail.trimmedOrNil,
            services: servicesList.isEmpty ? nil : servicesList,
            businessHours: hoursDict,
            hoursJson: hoursJson,
            slotMinutes: timeIncrementMinutes,
            bookingSlotMinutes: defaultAppointmentMinutes,
            minBookingMinutes: min,
            maxBookingMinutes: max,
            allowSameDay: allowSameDay
        )

        isSaving = true
        defer { isSaving = false }

        do {
            let response = try await PortalBackend.shared.upsertBookingSettings(
                businessId: businessId,
                settings: settings
            )
            profile.bookingBrandName = response.brandName ?? brandName
            profile.bookingOwnerEmail = response.ownerEmail ?? ownerEmail
            profile.bookingServicesText = servicesList.map { $0.name }.joined(separator: "\n")
            profile.bookingServicesJSON = encodeServices(servicesList) ?? ""
            profile.bookingHoursJSON = response.hoursJson ?? hoursJson ?? ""
            profile.bookingSlotMinutes = response.bookingSlotMinutes ?? defaultAppointmentMinutes
            profile.bookingTimeIncrementMinutes = response.slotMinutes ?? timeIncrementMinutes
            profile.bookingMinBookingMinutes = response.minBookingMinutes ?? min
            profile.bookingMaxBookingMinutes = response.maxBookingMinutes ?? max
            profile.bookingAllowSameDay = response.allowSameDay ?? allowSameDay
            try? modelContext.save()
            lastSyncedAt = Date()
            if showSyncedBanner {
                showSyncedNotice()
            }
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
            return false
        }

        return true
    }

    @MainActor
    private func scheduleAutoSave() {
        guard !isInitializing else { return }
        guard !isLoading else { return }
        guard !isRefreshing else { return }

        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            _ = await saveSettings(showErrors: false, showSyncedBanner: false)
        }
    }

    @MainActor
    private func showSyncedNotice() {
        withAnimation(.easeOut(duration: 0.2)) {
            showSyncedToast = true
        }
    }

    private func applyWeekdayHours() {
        guard let mon = hours.first(where: { $0.day == .mon }) else { return }
        for idx in hours.indices {
            let day = hours[idx].day
            if day == .mon || day == .tue || day == .wed || day == .thu || day == .fri {
                hours[idx].isOpen = mon.isOpen
                hours[idx].start = mon.start
                hours[idx].end = mon.end
            }
        }
    }

    private var defaultDurationOptions: [Int] {
        [15, 30, 45, 60, 90, 120]
    }

    private var serviceDurationOptions: [Int] {
        [15, 30, 45, 60, 90, 120, 150, 180, 240]
    }

    private var timeIncrementOptions: [Int] {
        [15, 30]
    }

    @MainActor
    private func addService() {
        let trimmed = newServiceName.trimmed
        guard !trimmed.isEmpty else { return }
        services.append(
            BookingServiceOption(name: trimmed, durationMinutes: newServiceDuration)
        )
        newServiceName = ""
        newServiceDuration = defaultAppointmentMinutes
    }

    private func deleteServices(at offsets: IndexSet) {
        services.remove(atOffsets: offsets)
    }

    private func moveServices(from source: IndexSet, to destination: Int) {
        services.move(fromOffsets: source, toOffset: destination)
    }

    private func encodeServices(_ services: [BookingServiceOption]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(services) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeServices(from json: String) -> [BookingServiceOption]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([BookingServiceOption].self, from: data)
    }

    private func roundedUpToIncrement(_ value: Int, increment: Int) -> Int {
        guard increment > 0 else { return value }
        let remainder = value % increment
        if remainder == 0 { return value }
        return value + (increment - remainder)
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}

private struct HoursRow: Identifiable, Equatable {
    let day: PortalWeekday
    var isOpen: Bool
    var start: Date
    var end: Date

    var id: String { day.rawValue }

    static func defaults() -> [HoursRow] {
        let start = timeDate(hour: 9, minute: 0)
        let end = timeDate(hour: 17, minute: 0)
        return PortalWeekday.allCases.map { day in
            HoursRow(day: day, isOpen: false, start: start, end: end)
        }
    }

    static func from(config: PortalHoursConfig) -> [HoursRow] {
        return PortalWeekday.allCases.map { day in
            let info = config.days[day] ?? PortalHoursDay(isOpen: false, start: nil, end: nil)
            let start = parseTime(info.start) ?? timeDate(hour: 9, minute: 0)
            let end = parseTime(info.end) ?? timeDate(hour: 17, minute: 0)
            return HoursRow(day: day, isOpen: info.isOpen, start: start, end: end)
        }
    }

    static func toConfig(from rows: [HoursRow]) -> PortalHoursConfig? {
        if rows.isEmpty { return nil }
        var map: [PortalWeekday: PortalHoursDay] = [:]
        for row in rows {
            let start = row.isOpen ? timeString(row.start) : nil
            let end = row.isOpen ? timeString(row.end) : nil
            map[row.day] = PortalHoursDay(isOpen: row.isOpen, start: start, end: end)
        }
        return PortalHoursConfig(days: map)
    }

    private static func timeDate(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func parseTime(_ input: String?) -> Date? {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let formats = ["HH:mm", "H:mm", "h:mma", "h:mm a", "ha"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: input.uppercased()) {
                return date
            }
        }
        return nil
    }
}

#Preview {
    BookingPortalCustomizeView(profile: BusinessProfile())
        .environmentObject(ActiveBusinessStore())
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedOrNil: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
}

private struct ChangeHandlers: ViewModifier {
    let bookingEnabled: Bool
    let bookingHoursText: String
    let bookingInstructions: String
    let brandName: String
    let ownerEmail: String
    let services: [BookingServiceOption]
    let hours: [HoursRow]
    let defaultAppointmentMinutes: Int
    let timeIncrementMinutes: Int
    let minBookingMinutesText: String
    let maxBookingMinutesText: String
    let allowSameDay: Bool
    let persist: () -> Void
    let autosave: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: bookingEnabled) { _, _ in persist() }
            .onChange(of: bookingHoursText) { _, _ in persist() }
            .onChange(of: bookingInstructions) { _, _ in persist() }
            .onChange(of: brandName) { _, _ in autosave() }
            .onChange(of: ownerEmail) { _, _ in autosave() }
            .onChange(of: services) { _, _ in autosave() }
            .onChange(of: hours) { _, _ in autosave() }
            .onChange(of: defaultAppointmentMinutes) { _, _ in autosave() }
            .onChange(of: timeIncrementMinutes) { _, _ in autosave() }
            .onChange(of: minBookingMinutesText) { _, _ in autosave() }
            .onChange(of: maxBookingMinutesText) { _, _ in autosave() }
            .onChange(of: allowSameDay) { _, _ in autosave() }
    }
}

private struct LoadAndRefreshHandler: ViewModifier {
    let onLoad: () -> Void
    let onRefresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { onLoad() }
            .task { await onRefresh() }
    }
}
