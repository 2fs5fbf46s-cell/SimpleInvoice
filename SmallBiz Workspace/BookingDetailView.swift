import SwiftUI
import Foundation

struct BookingDetailView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    let request: BookingRequestItem
    let onStatusChange: (String) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var currentStatus: String

    init(request: BookingRequestItem, onStatusChange: @escaping (String) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
        _currentStatus = State(initialValue: request.status)
    }

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
