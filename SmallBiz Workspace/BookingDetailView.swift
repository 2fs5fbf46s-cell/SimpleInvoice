import SwiftUI
import Foundation
import SwiftData

struct BookingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    let request: BookingRequestItem
    let onStatusChange: (String) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var currentStatus: String
    @State private var navigateToInvoice: Invoice? = nil
    @State private var navigateToJob: Job? = nil

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
        _currentStatus = State(initialValue: request.status)
    }

    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

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
                    Button("Approve") {
                        Task { await approveRequest() }
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
                    Text("Approve this request to enable conversions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Metadata") {
                detailRow("Request ID", request.requestId)
                detailRow("Business ID", request.businessId)
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
    }

    private var statusLabel: String {
        let key = currentStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    private func approveRequest() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let bizID = try resolveBusinessId()
            try await PortalBackend.shared.approveBookingRequest(
                businessId: bizID,
                requestId: request.requestId
            )
            currentStatus = "approved"
            onStatusChange("approved")
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
