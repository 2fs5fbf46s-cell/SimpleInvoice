import SwiftUI
import SwiftData

struct BookingsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Booking.startDate, order: .forward)
    private var bookings: [Booking]

    @State private var showNew = false
    @State private var searchText = ""

    private var filtered: [Booking] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return bookings }
        return bookings.filter {
            $0.title.lowercased().contains(q) ||
            ($0.client?.name ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Bookings",
                    systemImage: "calendar.badge.clock",
                    description: Text("Tap + to create your first booking.")
                )
            } else {
                ForEach(filtered) { b in
                    NavigationLink {
                        BookingDetailView(booking: b)
                    } label: {
                        bookingRow(b)
                    }
                }
                .onDelete(perform: deleteBookings)
            }
        }
        .navigationTitle("Bookings")
        .searchable(text: $searchText, prompt: "Search bookings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                NewBookingView()
            }
        }
    }

    private func bookingRow(_ b: Booking) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.title.isEmpty ? "Booking" : b.title)
                    .font(.headline)

                Spacer()

                Text(b.status.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(b.client?.name ?? "No customer")
                .foregroundStyle(.secondary)

            HStack {
                Text(b.startDate, style: .date)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(b.startDate, style: .time) – \(b.endDate, style: .time)")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func deleteBookings(at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(filtered[idx])
        }
        try? modelContext.save()
    }
}
