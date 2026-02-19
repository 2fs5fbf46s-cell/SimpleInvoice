import SwiftUI

struct BookingAnalyticsDetailListView: View {
    let title: String
    let bookings: [BookingRequestItem]
    let range: BookingAnalyticsRange
    let filter: BookingAnalyticsDetailFilter

    @State private var selectedRequest: BookingRequestItem? = nil

    private var filteredBookings: [BookingRequestItem] {
        bookings
            .filter { BookingAnalyticsEngine.matchesFilter($0, filter: filter) }
            .sorted { BookingAnalyticsEngine.bookingDate($0) > BookingAnalyticsEngine.bookingDate($1) }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                if filteredBookings.isEmpty {
                    ContentUnavailableView(
                        "No Matching Bookings",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No bookings match this filter for \(range.subtitle).")
                    )
                } else {
                    ForEach(filteredBookings) { booking in
                        Button {
                            selectedRequest = booking
                        } label: {
                            row(for: booking)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRequest) { request in
            BookingDetailView(request: request)
        }
    }

    private func row(for booking: BookingRequestItem) -> some View {
        let statusText = normalizedStatusLabel(booking.status)
        let chip = statusChip(for: statusText)
        let created = BookingAnalyticsEngine.bookingDate(booking)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName(for: booking))
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

            if let service = booking.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines),
               !service.isEmpty {
                Text(service)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(created, style: .date)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func displayName(for booking: BookingRequestItem) -> String {
        if let name = booking.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = booking.clientEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        if let phone = booking.clientPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            return phone
        }
        return "Unknown client"
    }

    private func normalizedStatusLabel(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "deposit_requested" { return "DEPOSIT REQUESTED" }
        if key == "approved" { return "APPROVED" }
        if key == "declined" { return "DECLINED" }
        if key == "pending" { return "PENDING" }
        if key == "deposit_paid" { return "DEPOSIT PAID" }
        return key.isEmpty ? "PENDING" : key.uppercased()
    }

    private func statusChip(for statusText: String) -> (fg: Color, bg: Color) {
        switch statusText {
        case "DEPOSIT REQUESTED":
            return (Color.yellow, Color.yellow.opacity(0.15))
        case "DEPOSIT PAID":
            return (SBWTheme.brandBlue, SBWTheme.brandBlue.opacity(0.16))
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
}
