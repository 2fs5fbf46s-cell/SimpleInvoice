import SwiftUI
import Foundation
import SwiftData

struct BookingsListView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext
    @Query private var jobs: [Job]
    @Query private var clients: [Client]
    @Query private var invoices: [Invoice]
    @Query private var profiles: [BusinessProfile]

    @State private var searchText = ""
    @State private var requests: [BookingRequestItem] = []
    @State private var selectedStatus: BookingAdminStatus = .pending
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var selectedRequest: BookingRequestItem? = nil

    private var taskKey: String {
        "\(activeBiz.activeBusinessID?.uuidString ?? "none")-\(selectedStatus.rawValue)"
    }

    private var filteredRequests: [BookingRequestItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let statusFiltered = requests.filter { matchesStatus($0.status, selected: selectedStatus) }
        guard !q.isEmpty else { return statusFiltered }

        return statusFiltered.filter {
            bookingClient($0).lowercased().contains(q) ||
            ($0.serviceType ?? "").lowercased().contains(q) ||
            ($0.clientEmail ?? "").lowercased().contains(q) ||
            ($0.clientPhone ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            List {
                Section {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(BookingAdminStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading bookings…")
                        Spacer()
                    }
                } else if filteredRequests.isEmpty {
                    ContentUnavailableView(
                        selectedStatus == .all ? "No Requests" : "No \(selectedStatus.label) Requests",
                        systemImage: "calendar.badge.clock",
                        description: Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          ? "New booking requests will appear here."
                                          : "Try a different search.")
                    )
                    .overlay(alignment: .center) {
                        if errorMessage != nil {
                            Button("Retry") {
                                Task { await loadRequests() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ForEach(filteredRequests) { request in
                        Button {
                            selectedRequest = request
                        } label: {
                            bookingRow(request)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Bookings")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search bookings"
        )
        .navigationDestination(item: $selectedRequest) { request in
            BookingDetailView(request: request) { newStatus in
                updateStatus(for: request.requestId, newStatus: newStatus)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadRequests() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task(id: taskKey) {
            await loadRequests()
        }
        .refreshable {
            await loadRequests()
        }
        .alert("Booking Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    // MARK: - Row UI (Option A polish)

    private func bookingRow(_ request: BookingRequestItem) -> some View {
        let statusText = normalizedStatusLabel(request.status)
        let chip = statusChip(for: statusText)
        let startDate = parseDate(request.requestedStart)

        return HStack(alignment: .top, spacing: 12) {
            // Leading icon chip (bookings)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AnyShapeStyle(SBWTheme.brandGradient.opacity(0.18)))
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bookingClient(request))
                        .font(.headline)

                    Spacer()

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chip.fg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(chip.bg)
                        .clipShape(Capsule())
                }

                if let service = request.serviceType, !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(service)
                        .foregroundStyle(.secondary)
                }

                if let startDate {
                    Text(startDate, style: .date)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Requested time pending")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 2)
    }

    private func normalizedStatusLabel(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if key == "deposit_requested" { return "DEPOSIT REQUESTED" }
        if key == "approved" { return "APPROVED" }
        if key == "declined" { return "DECLINED" }
        if key == "pending" { return "PENDING" }
        return key.isEmpty ? "PENDING" : key.uppercased()
    }

    private func statusChip(for statusText: String) -> (fg: Color, bg: Color) {
        let key = statusText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch key {
        case "DEPOSIT REQUESTED":
            return (Color.blue, Color.blue.opacity(0.12))
        case "APPROVED":
            return (SBWTheme.brandGreen, SBWTheme.brandGreen.opacity(0.12))
        case "DECLINED":
            return (Color.red, Color.red.opacity(0.12))
        case "PENDING":
            return (Color.orange, Color.orange.opacity(0.12))
        default:
            return (.secondary, Color.primary.opacity(0.06))
        }
    }

    private func bookingClient(_ request: BookingRequestItem) -> String {
        if let name = request.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = request.clientEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        if let phone = request.clientPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            return phone
        }
        return "No customer"
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let date = Self.isoWithFractional.date(from: raw) { return date }
        if let date = Self.isoPlain.date(from: raw) { return date }
        if let seconds = Double(raw) {
            let normalized = seconds > 10_000_000_000 ? seconds / 1000.0 : seconds
            return Date(timeIntervalSince1970: normalized)
        }
        return nil
    }

    @MainActor
    private func loadRequests() async {
        guard !isLoading else { return }
        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        } catch {
            // ignore: we'll show empty state below
        }

        guard let bizId = activeBiz.activeBusinessID else {
            requests = []
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await PortalBackend.shared.fetchBookingRequests(businessId: bizId)
            let mapped = response.map { dto in
                BookingRequestItem(
                    requestId: dto.requestId,
                    businessId: dto.businessId,
                    slug: dto.slug,
                    clientName: dto.clientName,
                    clientEmail: dto.clientEmail,
                    clientPhone: dto.clientPhone,
                    requestedStart: dto.requestedStart,
                    requestedEnd: dto.requestedEnd,
                    serviceType: dto.serviceType,
                    notes: dto.notes,
                    status: dto.status,
                    createdAtMs: dto.createdAtMs,
                    depositAmountCents: dto.depositAmountCents,
                    depositInvoiceId: dto.depositInvoiceId,
                    depositPaidAtMs: dto.depositPaidAtMs,
                    finalInvoiceId: dto.finalInvoiceId
                )
            }
            requests = mapped.sorted { lhs, rhs in
                let l = lhs.createdAtMs ?? 0
                let r = rhs.createdAtMs ?? 0
                return l > r
            }
            for request in requests where request.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "approved" {
                try? autoCreateApprovedArtifactsIfNeeded(request: request, businessID: bizId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func matchesStatus(_ raw: String, selected: BookingAdminStatus) -> Bool {
        if selected == .all { return true }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key == selected.rawValue
    }

    private func updateStatus(for requestId: String, newStatus: String) {
        let normalized = newStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        requests = requests.map { item in
            guard item.requestId == requestId else { return item }
            return BookingRequestItem(
                requestId: item.requestId,
                businessId: item.businessId,
                slug: item.slug,
                clientName: item.clientName,
                clientEmail: item.clientEmail,
                clientPhone: item.clientPhone,
                requestedStart: item.requestedStart,
                requestedEnd: item.requestedEnd,
                serviceType: item.serviceType,
                notes: item.notes,
                status: normalized,
                createdAtMs: item.createdAtMs,
                depositAmountCents: item.depositAmountCents,
                depositInvoiceId: item.depositInvoiceId,
                depositPaidAtMs: item.depositPaidAtMs,
                finalInvoiceId: item.finalInvoiceId
            )
        }
        scheduleRefreshAfterStatusChange()
    }

    private func autoCreateApprovedArtifactsIfNeeded(request: BookingRequestItem, businessID: UUID) throws {
        let requestId = request.requestId

        let existingJob = jobs.first {
            $0.businessID == businessID && $0.sourceBookingRequestId == requestId
        }
        let job: Job
        if let existingJob {
            job = existingJob
        } else {
            let client = try resolveOrCreateClient(request: request, businessID: businessID)
            let start = parseDate(request.requestedStart) ?? .now
            let end = parseDate(request.requestedEnd)
                ?? Calendar.current.date(byAdding: .hour, value: 2, to: start)
                ?? start
            let title = bookingJobTitle(request: request)
            let created = Job(
                businessID: businessID,
                clientID: client.id,
                title: title,
                notes: buildBookingNotes(request: request),
                startDate: start,
                endDate: end,
                locationName: "",
                status: "scheduled",
                sourceBookingRequestId: requestId
            )
            modelContext.insert(created)
            job = created
        }

        if invoices.contains(where: {
            $0.businessID == businessID &&
            $0.documentType == "invoice" &&
            $0.sourceBookingRequestId == requestId &&
            $0.invoiceNumber.uppercased().hasPrefix("FINAL-")
        }) {
            try modelContext.save()
            return
        }

        let client = try resolveOrCreateClient(request: request, businessID: businessID)
        let profile = profileEnsured(businessID: businessID)
        let finalNumber = "FINAL-\(requestId.suffix(6).uppercased())"
        let depositNote: String
        if let cents = request.depositAmountCents, cents > 0 {
            depositNote = String(format: "Deposit paid: $%.2f. Update final invoice total before sending.", Double(cents) / 100.0)
        } else {
            depositNote = "Deposit paid. Update final invoice total before sending."
        }

        let lineItem = LineItem(itemDescription: "Remaining Balance (after deposit)", quantity: 1, unitPrice: 0)
        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: finalNumber,
            issueDate: .now,
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            paymentTerms: "Net 14",
            notes: [buildBookingNotes(request: request), depositNote].joined(separator: "\n"),
            thankYou: profile.defaultThankYou,
            termsAndConditions: profile.defaultTerms,
            taxRate: 0,
            discountAmount: 0,
            isPaid: false,
            documentType: "invoice",
            sourceBookingRequestId: requestId,
            client: client,
            job: job,
            items: [lineItem]
        )
        modelContext.insert(invoice)
        try modelContext.save()
    }

    private func resolveOrCreateClient(request: BookingRequestItem, businessID: UUID) throws -> Client {
        let normalizedEmail = normalizeEmail(request.clientEmail)
        let normalizedPhone = normalizePhone(request.clientPhone)
        let normalizedName = request.clientName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        let scoped = clients.filter { $0.businessID == businessID }

        if let normalizedEmail {
            if let existing = scoped.first(where: { normalizeEmail($0.email) == normalizedEmail }) {
                return existing
            }
        }
        if let normalizedPhone {
            if let existing = scoped.first(where: { normalizePhone($0.phone) == normalizedPhone }) {
                return existing
            }
        }
        if !normalizedName.isEmpty {
            if let existing = scoped.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
            }) {
                return existing
            }
        }

        let newClient = Client(businessID: businessID)
        newClient.name = (request.clientName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (request.clientName ?? "")
            : (request.clientEmail ?? "New Client")
        newClient.email = request.clientEmail ?? ""
        newClient.phone = request.clientPhone ?? ""
        newClient.address = ""
        modelContext.insert(newClient)
        return newClient
    }

    private func normalizeEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizePhone(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber }
        return digits.isEmpty ? nil : digits
    }

    private func profileEnsured(businessID: UUID) -> BusinessProfile {
        if let existing = profiles.first(where: { $0.businessID == businessID }) {
            return existing
        }
        let created = BusinessProfile(businessID: businessID)
        modelContext.insert(created)
        return created
    }

    private func bookingJobTitle(request: BookingRequestItem) -> String {
        if let service = request.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !service.isEmpty {
            return service
        }
        return "Booking Job"
    }

    private func buildBookingNotes(request: BookingRequestItem) -> String {
        var lines: [String] = []
        lines.append("Booking Request")
        lines.append("Request ID: \(request.requestId)")
        if let name = request.clientName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Client Name: \(name)")
        }
        if let email = request.clientEmail, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Client Email: \(email)")
        }
        if let phone = request.clientPhone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Client Phone: \(phone)")
        }
        if let service = request.serviceType, !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Service: \(service)")
        }
        if let start = parseDate(request.requestedStart) {
            lines.append("Requested Start: \(dateFormatter.string(from: start))")
        }
        if let end = parseDate(request.requestedEnd) {
            lines.append("Requested End: \(dateFormatter.string(from: end))")
        }
        if let notes = request.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Notes: \(notes)")
        }
        return lines.joined(separator: "\n")
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    @MainActor
    private func scheduleRefreshAfterStatusChange() {
        guard selectedStatus != .all else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await loadRequests()
        }
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

struct BookingRequestItem: Identifiable, Hashable {
    let requestId: String
    let businessId: String
    let slug: String?
    let clientName: String?
    let clientEmail: String?
    let clientPhone: String?
    let requestedStart: String?
    let requestedEnd: String?
    let serviceType: String?
    let notes: String?
    let status: String
    let createdAtMs: Int?
    let depositAmountCents: Int?
    let depositInvoiceId: String?
    let depositPaidAtMs: Int?
    let finalInvoiceId: String?

    var id: String { requestId }
}
