import SwiftUI
import Foundation
import SwiftData
import UIKit

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
    @State private var lastDepositPortalURL: URL? = nil
    @State private var lastDepositSendWarning: String? = nil

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
        _currentStatus = State(initialValue: request.status)
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
        .onAppear {
            Task {
                if isApproved {
                    await autoCreateApprovedArtifactsIfNeeded()
                }
            }
        }
        .onChange(of: currentStatus) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "approved" {
                Task { await autoCreateApprovedArtifactsIfNeeded() }
            }
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

    @MainActor
    private func autoCreateApprovedArtifactsIfNeeded() async {
        guard isApproved else { return }
        do {
            let bizID = try resolveBusinessId()
            let job = try createOrReuseJobForBooking(businessID: bizID)
            _ = try createOrReuseFinalInvoiceDraft(businessID: bizID, job: job)
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
            let client = try resolveOrCreateClient(businessID: bizID)
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
            let client = try resolveOrCreateClient(businessID: bizID)

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
            let client = try resolveOrCreateClient(businessID: bizID)
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

            modelContext.insert(job)
            try modelContext.save()
            navigateToJob = job
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createOrReuseJobForBooking(businessID: UUID) throws -> Job {
        // Prevent duplicates: if a job already exists for this booking request, reuse it.
        let reqId = request.requestId
        let descriptor = FetchDescriptor<Job>(predicate: #Predicate<Job> { job in
            job.businessID == businessID && job.sourceBookingRequestId == reqId
        })

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let client = try resolveOrCreateClient(businessID: businessID)
        let title = bookingJobTitle()

        let start = parseDate(request.requestedStart) ?? .now
        let end = parseDate(request.requestedEnd)
            ?? Calendar.current.date(byAdding: .hour, value: 2, to: start)
            ?? start

        let job = Job(
            businessID: businessID,
            clientID: client.id,
            title: title,
            notes: buildBookingNotes(),
            startDate: start,
            endDate: end,
            locationName: "",
            status: "scheduled",
            sourceBookingRequestId: reqId
        )

        modelContext.insert(job)
        try modelContext.save()
        return job
    }

    @MainActor
    private func createOrReuseFinalInvoiceDraft(businessID: UUID, job: Job) throws -> Invoice {
        let reqId = request.requestId
        if let existing = invoices.first(where: {
            $0.businessID == businessID &&
            $0.documentType == "invoice" &&
            $0.sourceBookingRequestId == reqId &&
            $0.invoiceNumber.uppercased().hasPrefix("FINAL-")
        }) {
            return existing
        }

        let client = try resolveOrCreateClient(businessID: businessID)
        let profile = profileEnsured(businessID: businessID)
        let finalNumber = "FINAL-\(reqId.suffix(6).uppercased())"
        let paidCents = request.depositAmountCents ?? 0
        let depositNote = paidCents > 0
            ? String(format: "Deposit paid: $%.2f. Update final invoice total before sending.", Double(paidCents) / 100.0)
            : "Deposit paid. Update final invoice total before sending."
        let lineItem = LineItem(itemDescription: "Remaining Balance (after deposit)", quantity: 1, unitPrice: 0)

        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: finalNumber,
            issueDate: .now,
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            paymentTerms: "Net 14",
            notes: [buildBookingNotes(), depositNote].joined(separator: "\n"),
            thankYou: profile.defaultThankYou,
            termsAndConditions: profile.defaultTerms,
            taxRate: 0,
            discountAmount: 0,
            isPaid: false,
            documentType: "invoice",
            sourceBookingRequestId: reqId,
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

    @MainActor
    private func resolveOrCreateClient(businessID: UUID) throws -> Client {
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
        try modelContext.save()
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
