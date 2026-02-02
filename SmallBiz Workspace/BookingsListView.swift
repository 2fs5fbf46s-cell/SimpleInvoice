import SwiftUI
import SwiftData

struct BookingsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: \Booking.startDate, order: .forward)
    private var bookings: [Booking]

    @State private var showNew = false
    @State private var searchText = ""

    // MARK: - Scoped bookings (active business)
    // Booking currently has no businessID in your models.swift — so we scope by client.businessID when possible.
    private var scopedBookings: [Booking] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return bookings.filter { b in
            guard let c = b.client else { return true } // keep unassigned bookings visible
            return c.businessID == bizID
        }
    }

    private var filtered: [Booking] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return scopedBookings }

        return scopedBookings.filter {
            $0.title.lowercased().contains(q) ||
            ($0.client?.name ?? "").lowercased().contains(q)
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
                if filtered.isEmpty {
                    ContentUnavailableView(
                        scopedBookings.isEmpty ? "No Bookings" : "No Results",
                        systemImage: "calendar.badge.clock",
                        description: Text(scopedBookings.isEmpty
                                          ? "Tap + to create your first booking."
                                          : "Try a different search.")
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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Bookings")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search bookings"
        )
        .settingsGear { BusinessProfileView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { NewBookingView() }
        }
    }

    // MARK: - Row UI (Option A polish)

    private func bookingRow(_ b: Booking) -> some View {
        let statusText = normalizedBookingStatusLabel(b.status)
        let chip = SBWTheme.chip(forStatus: statusText)

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
                    Text(b.title.isEmpty ? "Booking" : b.title)
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
            .padding(.vertical, 4)
        }
        .padding(.vertical, 2)
    }

    private func normalizedBookingStatusLabel(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if key == "completed" { return "COMPLETED" }
        if key == "canceled" || key == "cancelled" { return "CANCELED" }
        return "SCHEDULED" // your default
    }

    // MARK: - Deletes

    private func deleteBookings(at offsets: IndexSet) {
        for idx in offsets {
            guard idx < filtered.count else { continue }
            modelContext.delete(filtered[idx])
        }
        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }
}
