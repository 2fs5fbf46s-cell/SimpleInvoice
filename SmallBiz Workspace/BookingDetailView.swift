import SwiftUI
import Foundation
import SwiftData
import UIKit

struct BookingIdentity {
    let requestId: String
    let businessID: UUID
    let clientName: String?
    let clientEmail: String?
    let clientPhone: String?
    let serviceType: String?

    init(businessID: UUID, booking: BookingRequestItem) {
        self.requestId = booking.requestId
        self.businessID = businessID
        self.clientName = booking.clientName
        self.clientEmail = booking.clientEmail
        self.clientPhone = booking.clientPhone
        self.serviceType = booking.serviceType
    }

    var displayName: String {
        if let service = serviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !service.isEmpty {
            return service
        }
        if let name = clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = clientEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return "Booking"
    }
}

private func normalizedBookingEmail(_ email: String?) -> String? {
    guard let email else { return nil }
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedBookingPhone(_ phone: String?) -> String? {
    guard let phone else { return nil }
    let digits = phone.filter { $0.isNumber }
    return digits.isEmpty ? nil : digits
}

private func normalizedBookingName(_ name: String?) -> String? {
    guard let name else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? nil : trimmed
}

private func parseBookingDate(_ raw: String?) -> Date? {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    if let date = bookingISOWithFractional.date(from: raw) { return date }
    if let date = bookingISOPlain.date(from: raw) { return date }
    if let seconds = Double(raw) {
        let normalized = seconds > 10_000_000_000 ? seconds / 1000.0 : seconds
        return Date(timeIntervalSince1970: normalized)
    }
    return nil
}

private func bookingJobTitle(for booking: BookingRequestItem) -> String {
    if let service = booking.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !service.isEmpty {
        return "Booking: \(service)"
    }
    if let name = booking.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        return "Booking: \(name)"
    }
    return "Booking: Booking"
}

private func bookingNotes(from booking: BookingRequestItem) -> String {
    var lines: [String] = []
    lines.append("Booking Request")
    lines.append("Request ID: \(booking.requestId)")
    if let name = booking.clientName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Client Name: \(name)")
    }
    if let email = booking.clientEmail, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Client Email: \(email)")
    }
    if let phone = booking.clientPhone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Client Phone: \(phone)")
    }
    if let service = booking.serviceType, !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Service: \(service)")
    }
    if let start = parseBookingDate(booking.requestedStart) {
        lines.append("Requested Start: \(bookingDateFormatter.string(from: start))")
    }
    if let end = parseBookingDate(booking.requestedEnd) {
        lines.append("Requested End: \(bookingDateFormatter.string(from: end))")
    }
    if let notes = booking.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Notes: \(notes)")
    }
    return lines.joined(separator: "\n")
}

private func requiredFinalInvoiceNotes(for booking: BookingRequestItem) -> [String] {
    var lines = [
        "FINAL invoice draft created from Booking Request",
        "Booking Request ID: \(booking.requestId)"
    ]

    if let cents = booking.depositAmountCents {
        let amount = max(0, cents)
        lines.append(String(format: "Deposit: $%.2f", Double(amount) / 100.0))
    }

    if booking.depositPaidAtMs != nil {
        let amount = max(0, booking.depositAmountCents ?? 0)
        lines.append(String(format: "Deposit paid: $%.2f", Double(amount) / 100.0))
    }

    return lines
}

private func mergedFinalInvoiceNotes(existing: String, booking: BookingRequestItem) -> String {
    var lines = existing
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    for required in requiredFinalInvoiceNotes(for: booking) where !lines.contains(required) {
        lines.append(required)
    }
    return lines.joined(separator: "\n")
}

private func upsertRemainingBalanceLineItem(
    invoice: Invoice,
    remainingCents: Int
) -> Bool {
    let targetDescription = "Remaining Balance (after deposit)"
    let unitPrice = Double(max(0, remainingCents)) / 100.0
    var items = invoice.items ?? []
    var updated = false

    if let index = items.firstIndex(where: { $0.itemDescription == targetDescription }) {
        let existing = items[index]
        if existing.quantity != 1 {
            existing.quantity = 1
            updated = true
        }
        if existing.unitPrice != unitPrice {
            existing.unitPrice = unitPrice
            updated = true
        }
    } else {
        let lineItem = LineItem(
            itemDescription: targetDescription,
            quantity: 1,
            unitPrice: unitPrice
        )
        lineItem.invoice = invoice
        items.append(lineItem)
        invoice.items = items
        updated = true
    }

    return updated
}

private func mergedRemainingNotes(
    existing: String,
    totalCents: Int,
    depositCents: Int,
    remainingCents: Int
) -> String {
    let prefixTotal = "Total:"
    let prefixDeposit = "Deposit:"
    let prefixRemaining = "Remaining:"

    var lines = existing
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter {
            !$0.hasPrefix(prefixTotal) &&
            !$0.hasPrefix(prefixDeposit) &&
            !$0.hasPrefix(prefixRemaining)
        }

    lines.append(String(format: "Total: $%.2f", Double(max(0, totalCents)) / 100.0))
    lines.append(String(format: "Deposit: $%.2f", Double(max(0, depositCents)) / 100.0))
    lines.append(String(format: "Remaining: $%.2f", Double(max(0, remainingCents)) / 100.0))

    return lines.joined(separator: "\n")
}

private let bookingDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private let bookingISOWithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let bookingISOPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

@MainActor
func resolveOrCreateClientFromBooking(
    businessID: UUID,
    booking: BookingRequestItem,
    modelContext: ModelContext
) throws -> Client {
    let allClients = try modelContext.fetch(FetchDescriptor<Client>())
    let scoped = allClients.filter { $0.businessID == businessID }

    let normalizedEmail = normalizedBookingEmail(booking.clientEmail)
    if let normalizedEmail,
       let existing = scoped.first(where: { normalizedBookingEmail($0.email) == normalizedEmail }) {
        return existing
    }

    let normalizedPhone = normalizedBookingPhone(booking.clientPhone)
    if let normalizedPhone,
       let existing = scoped.first(where: { normalizedBookingPhone($0.phone) == normalizedPhone }) {
        return existing
    }

    let normalizedName = normalizedBookingName(booking.clientName)
    if let normalizedName,
       let existing = scoped.first(where: { normalizedBookingName($0.name) == normalizedName }) {
        return existing
    }

    let fallbackName = booking.clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackEmail = booking.clientEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    let name: String
    if let fallbackName, !fallbackName.isEmpty {
        name = fallbackName
    } else if let fallbackEmail, !fallbackEmail.isEmpty {
        name = fallbackEmail
    } else {
        name = "Booking Client"
    }

    let newClient = Client(businessID: businessID)
    newClient.name = name
    newClient.email = booking.clientEmail ?? ""
    newClient.phone = booking.clientPhone ?? ""
    newClient.address = ""

    modelContext.insert(newClient)
    try modelContext.save()
    return newClient
}

@MainActor
func createOrReuseJobForBooking(
    businessID: UUID,
    booking: BookingRequestItem,
    client: Client,
    modelContext: ModelContext
) throws -> Job {
    let allJobs = try modelContext.fetch(FetchDescriptor<Job>())
    if let existing = allJobs.first(where: {
        $0.businessID == businessID &&
        $0.sourceBookingRequestId == booking.requestId
    }) {
        var updated = false
        let now = Date()
        if existing.clientID != client.id {
            existing.clientID = client.id
            updated = true
        }
        if existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            existing.title = bookingJobTitle(for: booking)
            updated = true
        }
        if existing.stage == .completed && existing.startDate >= now {
            existing.stage = .booked
            updated = true
        }
        if updated {
            try modelContext.save()
        }
        return existing
    }

    let start = parseBookingDate(booking.requestedStart) ?? .now
    let end = parseBookingDate(booking.requestedEnd)
        ?? Calendar.current.date(byAdding: .hour, value: 2, to: start)
        ?? start

    let job = Job(
        businessID: businessID,
        clientID: client.id,
        title: bookingJobTitle(for: booking),
        notes: bookingNotes(from: booking),
        startDate: start,
        endDate: end,
        locationName: "",
        status: "scheduled",
        sourceBookingRequestId: booking.requestId
    )
    job.stage = .booked
    modelContext.insert(job)
    try modelContext.save()
    return job
}

@MainActor
func createOrReuseFinalInvoiceForBooking(
    businessID: UUID,
    booking: BookingRequestItem,
    client: Client,
    job: Job,
    profile: BusinessProfile,
    modelContext: ModelContext
) throws -> Invoice {
    let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
    let totalCents = booking.bookingTotalAmountCents
    let depositCents = max(0, booking.depositAmountCents ?? 0)
    if let existing = allInvoices.first(where: {
        $0.businessID == businessID &&
        $0.documentType == "invoice" &&
        $0.sourceBookingRequestId == booking.requestId
    }) {
        var updated = false
        if existing.client?.id != client.id {
            existing.client = client
            updated = true
        }
        if existing.job?.id != job.id {
            existing.job = job
            updated = true
        }
        if existing.documentType != "invoice" {
            existing.documentType = "invoice"
            updated = true
        }
        if existing.sourceBookingRequestId != booking.requestId {
            existing.sourceBookingRequestId = booking.requestId
            updated = true
        }
        if (existing.items ?? []).isEmpty {
            let lineItem = LineItem(
                itemDescription: "Remaining Balance (after deposit)",
                quantity: 1,
                unitPrice: 0
            )
            lineItem.invoice = existing
            existing.items = [lineItem]
            updated = true
        }
        let mergedNotes = mergedFinalInvoiceNotes(existing: existing.notes, booking: booking)
        if existing.notes != mergedNotes {
            existing.notes = mergedNotes
            updated = true
        }
        if let totalCents {
            let remainingCents = max(totalCents - depositCents, 0)
            if upsertRemainingBalanceLineItem(invoice: existing, remainingCents: remainingCents) {
                updated = true
            }
            let financialNotes = mergedRemainingNotes(
                existing: existing.notes,
                totalCents: totalCents,
                depositCents: depositCents,
                remainingCents: remainingCents
            )
            if existing.notes != financialNotes {
                existing.notes = financialNotes
                updated = true
            }
        }
        if updated {
            try modelContext.save()
        }
        return existing
    }
    let number = InvoiceNumberGenerator.generateNextNumber(profile: profile)
    let initialRemainingCents = totalCents != nil ? max((totalCents ?? 0) - depositCents, 0) : 0

    let lineItem = LineItem(
        itemDescription: "Remaining Balance (after deposit)",
        quantity: 1,
        unitPrice: totalCents != nil ? Double(initialRemainingCents) / 100.0 : 0
    )

    var notes = requiredFinalInvoiceNotes(for: booking).joined(separator: "\n")
    if let totalCents {
        let remainingCents = max(totalCents - depositCents, 0)
        notes = mergedRemainingNotes(
            existing: notes,
            totalCents: totalCents,
            depositCents: depositCents,
            remainingCents: remainingCents
        )
    }

    let invoice = Invoice(
        businessID: businessID,
        invoiceNumber: number,
        issueDate: .now,
        dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
        paymentTerms: "Net 14",
        notes: notes,
        thankYou: profile.defaultThankYou,
        termsAndConditions: profile.defaultTerms,
        taxRate: 0,
        discountAmount: 0,
        isPaid: false,
        documentType: "invoice",
        sourceBookingRequestId: booking.requestId,
        client: client,
        job: job,
        items: [lineItem]
    )

    if let preferredRaw = client.preferredInvoiceTemplateKey,
       let preferred = InvoiceTemplateKey.from(preferredRaw) {
        invoice.invoiceTemplateKeyOverride = preferred.rawValue
    }

    modelContext.insert(invoice)
    try modelContext.save()
    return invoice
}

struct BookingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    let request: BookingRequestItem
    let onStatusChange: (String) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var currentStatus: String
    @State private var navigateToInvoice: Invoice? = nil
    @State private var navigateToJob: Job? = nil
    @State private var showDepositSheet = false
    @State private var depositAmountText = "100.00"
    @State private var totalAmountText = ""
    @State private var savedBookingTotalAmountCents: Int? = nil
    @State private var lastDepositPortalURL: URL? = nil
    @State private var lastDepositSendWarning: String? = nil

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
        _currentStatus = State(initialValue: request.status)
        _savedBookingTotalAmountCents = State(initialValue: request.bookingTotalAmountCents)
        if let cents = request.bookingTotalAmountCents {
            _totalAmountText = State(initialValue: String(format: "%.2f", Double(max(0, cents)) / 100.0))
        } else {
            _totalAmountText = State(initialValue: "")
        }
    }

    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]
    @Query private var jobs: [Job]
    @Query private var invoices: [Invoice]

    var body: some View {
        Form {
            Section("Details") {
                detailRow("Status", statusLabel)
                if let serviceName = request.serviceType, !serviceName.isEmpty {
                    detailRow("Service", serviceName)
                }
            }

            Section("Customer") {
                detailRow("Name", request.clientName ?? "Unknown")
                if let email = request.clientEmail, !email.isEmpty {
                    detailRow("Email", email)
                }
                if let phone = request.clientPhone, !phone.isEmpty {
                    detailRow("Phone", phone)
                }
            }

            Section("Schedule") {
                if let start = parseDate(request.requestedStart) {
                    detailRow("Start", dateFormatter.string(from: start))
                } else {
                    detailRow("Start", "Pending")
                }
                if let end = parseDate(request.requestedEnd) {
                    detailRow("End", dateFormatter.string(from: end))
                } else {
                    detailRow("End", "Pending")
                }
            }

            if let notes = request.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldShowRemainingCapture {
                Section("Payment Summary") {
                    TextField("Total (optional)", text: $totalAmountText)
                        .keyboardType(.decimalPad)

                    if let depositCents = request.depositAmountCents {
                        detailRow("Deposit", currencyString(fromCents: depositCents))
                    } else {
                        detailRow("Deposit", "Not set")
                    }

                    if let remaining = computedRemainingCents {
                        detailRow("Remaining", currencyString(fromCents: remaining))
                    } else {
                        detailRow("Remaining", "Unknown")
                        Text("Add the total to auto-calculate remaining balance on FINAL invoice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Total") {
                        Task { await saveBookingTotal() }
                    }
                    .disabled(isSubmitting || parseOptionalCurrencyCents(from: totalAmountText) == nil)
                }
            }

            if isPending {
                Section("Actions") {
                    Button("Request Deposit") {
                        depositAmountText = request.depositAmountCents != nil
                            ? String(format: "%.2f", Double(request.depositAmountCents ?? 0) / 100.0)
                            : "100.00"
                        showDepositSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)

                    Button("Decline", role: .destructive) {
                        Task { await declineRequest() }
                    }
                    .disabled(isSubmitting)

                    if isSubmitting {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }

            if let portalURL = lastDepositPortalURL {
                Section("Deposit Link") {
                    Text("Deposit link ready.")
                        .foregroundStyle(.secondary)
                    Button("Copy Link") {
                        UIPasteboard.general.string = portalURL.absoluteString
                    }
                    Button("Open Link") {
                        openURL(portalURL)
                    }
                    if let warning = lastDepositSendWarning, !warning.isEmpty {
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Create From Booking") {
                Button("Create Estimate") {
                    Task { await createEstimate() }
                }
                .disabled(!isApproved || isSubmitting)

                Button("Create Job") {
                    Task { await createJob() }
                }
                .disabled(!isApproved || isSubmitting)

                Button("Create Invoice") {
                    Task { await createInvoice() }
                }
                .disabled(!isApproved || isSubmitting)

                if let finalInvoice = existingFinalInvoiceForBooking {
                    Button("Open Final Invoice") {
                        navigateToInvoice = finalInvoice
                    }
                    .disabled(isSubmitting)
#if DEBUG
                    if let linkedClient = finalInvoice.client {
                        Text("Linked Client: \(linkedClient.name) (\(shortID(linkedClient.id)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let linkedJob = finalInvoice.job {
                        Text("Linked Job: \(linkedJob.title) (\(shortID(linkedJob.id)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Linked Invoice: \(finalInvoice.invoiceNumber) (\(shortID(finalInvoice.id)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
#endif
                }

                if !isApproved {
                    Text("Approved bookings enable conversions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Metadata") {
                detailRow("Request ID", request.requestId)
                detailRow("Business ID", request.businessId)
                if let depositInvoiceId = request.depositInvoiceId, !depositInvoiceId.isEmpty {
                    detailRow("Deposit Invoice", depositInvoiceId)
                }
                if let createdAt = dateFromMs(request.createdAtMs) {
                    detailRow("Submitted", dateFormatter.string(from: createdAt))
                }
            }
        }
        .navigationTitle("Booking Request")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Booking Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .navigationDestination(item: $navigateToInvoice) { invoice in
            InvoiceDetailView(invoice: invoice)
        }
        .navigationDestination(item: $navigateToJob) { job in
            JobDetailView(job: job)
        }
        .sheet(isPresented: $showDepositSheet) {
            depositSheet
        }
    }

    private var statusLabel: String {
        let key = currentStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "deposit_requested" { return "Deposit Requested" }
        if key == "approved" { return "Approved" }
        if key == "declined" { return "Declined" }
        if key == "pending" { return "Pending" }
        return key.isEmpty ? "Pending" : key.capitalized
    }

    private var isPending: Bool {
        currentStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending"
    }

    private var isApproved: Bool {
        currentStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "approved"
    }

    private var shouldShowRemainingCapture: Bool {
        let key = currentStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key == "deposit_requested" || key == "approved"
    }

    private var currentTotalAmountCents: Int? {
        parseOptionalCurrencyCents(from: totalAmountText) ?? savedBookingTotalAmountCents
    }

    private var computedRemainingCents: Int? {
        guard let totalCents = currentTotalAmountCents else { return nil }
        let depositCents = max(0, request.depositAmountCents ?? 0)
        return max(totalCents - depositCents, 0)
    }

    private var existingFinalInvoiceForBooking: Invoice? {
        let requestId = request.requestId
        let businessID = activeBiz.activeBusinessID ?? UUID(uuidString: request.businessId)
        return invoices.first(where: {
            $0.documentType == "invoice" &&
            $0.sourceBookingRequestId == requestId &&
            (businessID == nil || $0.businessID == businessID)
        })
    }

    private var depositSheet: some View {
        NavigationStack {
            Form {
                Section("Deposit Amount") {
                    TextField("100.00", text: $depositAmountText)
                        .keyboardType(.decimalPad)
                    Text("USD")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Request Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDepositSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        showDepositSheet = false
                        Task { await requestDeposit() }
                    }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
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

    private func dateFromMs(_ value: Int?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? Double(value) / 1000.0 : Double(value)
        return Date(timeIntervalSince1970: seconds)
    }

    @MainActor
    private func requestDeposit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            let depositAmountCents = parseDepositAmountCents(from: depositAmountText)
            let businessName = profiles.first(where: { $0.businessID == bizID })?.name
            let response = try await PortalBackend.shared.requestBookingDeposit(
                businessId: bizID,
                requestId: request.requestId,
                depositAmountCents: depositAmountCents,
                clientEmail: request.clientEmail,
                clientPhone: request.clientPhone,
                businessName: businessName,
                sendEmail: true,
                sendSms: false
            )
            currentStatus = response.status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (response.status ?? "deposit_requested")
                : "deposit_requested"
            onStatusChange(currentStatus)
            if let urlString = response.portalUrl, let url = URL(string: urlString) {
                lastDepositPortalURL = url
            }
            if let warnings = response.warnings, !warnings.isEmpty {
                lastDepositSendWarning = warnings.joined(separator: ", ")
            } else {
                lastDepositSendWarning = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func declineRequest() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            try await PortalBackend.shared.declineBookingRequest(
                businessId: bizID,
                requestId: request.requestId
            )
            currentStatus = "declined"
            onStatusChange("declined")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveBusinessId() throws -> UUID {
        if let active = activeBiz.activeBusinessID { return active }
        if let parsed = UUID(uuidString: request.businessId) { return parsed }
        throw NSError(domain: "Booking", code: 0, userInfo: [NSLocalizedDescriptionKey: "No active business selected."])
    }

    private func parseDepositAmountCents(from text: String) -> Int {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        if cleaned.isEmpty { return 10_000 }
        if let amount = Double(cleaned), amount > 0 {
            return Int((amount * 100.0).rounded())
        }
        return 10_000
    }

    private func parseOptionalCurrencyCents(from text: String) -> Int? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        guard let amount = Double(cleaned), amount > 0 else { return nil }
        return Int((amount * 100.0).rounded())
    }

    private func currencyString(fromCents cents: Int) -> String {
        String(format: "$%.2f", Double(max(0, cents)) / 100.0)
    }

    @MainActor
    private func saveBookingTotal() async {
        guard !isSubmitting else { return }
        guard let totalAmountCents = parseOptionalCurrencyCents(from: totalAmountText) else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            try await PortalBackend.shared.setBookingTotal(
                businessId: bizID,
                requestId: request.requestId,
                totalAmountCents: totalAmountCents
            )
            savedBookingTotalAmountCents = totalAmountCents

            if isApproved {
                let profile = profileEnsured(businessID: bizID)
                let client = try resolveOrCreateClientFromBooking(
                    businessID: bizID,
                    booking: request,
                    modelContext: modelContext
                )
                let job = try createOrReuseJobForBooking(
                    businessID: bizID,
                    booking: request,
                    client: client,
                    modelContext: modelContext
                )
                let updatedBooking = BookingRequestItem(
                    requestId: request.requestId,
                    businessId: request.businessId,
                    slug: request.slug,
                    clientName: request.clientName,
                    clientEmail: request.clientEmail,
                    clientPhone: request.clientPhone,
                    requestedStart: request.requestedStart,
                    requestedEnd: request.requestedEnd,
                    serviceType: request.serviceType,
                    notes: request.notes,
                    status: currentStatus,
                    createdAtMs: request.createdAtMs,
                    bookingTotalAmountCents: totalAmountCents,
                    depositAmountCents: request.depositAmountCents,
                    depositInvoiceId: request.depositInvoiceId,
                    depositPaidAtMs: request.depositPaidAtMs,
                    finalInvoiceId: request.finalInvoiceId
                )
                _ = try createOrReuseFinalInvoiceForBooking(
                    businessID: bizID,
                    booking: updatedBooking,
                    client: client,
                    job: job,
                    profile: profile,
                    modelContext: modelContext
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createEstimate() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            let client = try resolveOrCreateClientFromBooking(
                businessID: bizID,
                booking: request,
                modelContext: modelContext
            )
            let number = generateEstimateDraftNumber()

            let estimate = Invoice(
                businessID: bizID,
                invoiceNumber: number,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                paymentTerms: "Net 14",
                notes: buildBookingNotes(),
                thankYou: "",
                termsAndConditions: "",
                taxRate: 0,
                discountAmount: 0,
                isPaid: false,
                documentType: "estimate",
                sourceBookingRequestId: request.requestId,
                client: client,
                job: nil,
                items: []
            )
            estimate.estimateStatus = "draft"
            estimate.estimateAcceptedAt = nil

            modelContext.insert(estimate)
            try modelContext.save()
            navigateToInvoice = estimate
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createInvoice() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            let profile = profileEnsured(businessID: bizID)
            let number = InvoiceNumberGenerator.generateNextNumber(profile: profile)
            let client = try resolveOrCreateClientFromBooking(
                businessID: bizID,
                booking: request,
                modelContext: modelContext
            )

            let invoice = Invoice(
                businessID: bizID,
                invoiceNumber: number,
                issueDate: .now,
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                paymentTerms: "Net 14",
                notes: buildBookingNotes(),
                thankYou: profile.defaultThankYou,
                termsAndConditions: profile.defaultTerms,
                taxRate: 0,
                discountAmount: 0,
                isPaid: false,
                documentType: "invoice",
                sourceBookingRequestId: request.requestId,
                client: client,
                job: nil,
                items: []
            )

            if let preferredRaw = client.preferredInvoiceTemplateKey,
               let preferred = InvoiceTemplateKey.from(preferredRaw) {
                invoice.invoiceTemplateKeyOverride = preferred.rawValue
            }

            modelContext.insert(invoice)
            try modelContext.save()
            navigateToInvoice = invoice
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    @MainActor
    private func createJob() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            let client = try resolveOrCreateClientFromBooking(
                businessID: bizID,
                booking: request,
                modelContext: modelContext
            )
            let title = bookingJobTitle()

            let start = parseDate(request.requestedStart) ?? .now
            let end = parseDate(request.requestedEnd)
                ?? Calendar.current.date(byAdding: .hour, value: 2, to: start)
                ?? start

            let job = Job(
                businessID: bizID,
                clientID: client.id,
                title: title,
                notes: buildBookingNotes(),
                startDate: start,
                endDate: end,
                locationName: "",
                status: "scheduled",
                sourceBookingRequestId: request.requestId
            )
            job.stage = .booked

            modelContext.insert(job)
            try modelContext.save()
            navigateToJob = job
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func profileEnsured(businessID: UUID) -> BusinessProfile {
        if let existing = profiles.first(where: { $0.businessID == businessID }) {
            return existing
        }

        let created = BusinessProfile(businessID: businessID)
        modelContext.insert(created)
        return created
    }

    private func buildBookingNotes() -> String {
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
            lines.append("Service Type: \(service)")
        }

        if let start = parseDate(request.requestedStart) {
            lines.append("Requested Start: \(dateFormatter.string(from: start))")
        } else {
            lines.append("Requested Start: Pending")
        }

        if let end = parseDate(request.requestedEnd) {
            lines.append("Requested End: \(dateFormatter.string(from: end))")
        } else {
            lines.append("Requested End: Pending")
        }

        lines.append("Notes:")
        if let notes = request.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(notes)
        } else {
            lines.append("None")
        }

        return lines.joined(separator: "\n")
    }

    private func bookingJobTitle() -> String {
        let service = request.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let service, !service.isEmpty {
            return "Booking: \(service)"
        }
        let name = request.clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return "Booking: \(name)"
        }
        return "Booking"
    }

    private func generateEstimateDraftNumber() -> String {
        let df = DateFormatter()
        df.dateFormat = "EST-DRAFT-yyyyMMdd-HHmmss"
        return df.string(from: Date())
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var dateFormatter: DateFormatter { Self.dateFormatter }
}
