//
//  BookingListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

private enum BookingListFilter: String, CaseIterable {
    case open = "Open"
    case upcoming = "Upcoming"
    case past = "Past"
    case declined = "Declined"
    case all = "All"
}

private struct BookingGroup: Identifiable {
    let title: String
    let bookings: [BookingRequestItem]
    var id: String { title }
}

/// Booking requests, grouped by what each needs: an answer, a deposit, or
/// nothing (upcoming and past).
///
/// The old list sorted everything by when it was requested, showed the date
/// but not the time, and — on every load and every filter tap — created a
/// client, a job and a $0 invoice for each confirmed booking. Opening this
/// list changes nothing; a confirmed booking gets its client and job once,
/// in BookingWorkSetup.
struct BookingListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @State private var bookings: [BookingRequestItem] = []
    @State private var searchText = ""
    @State private var filter: BookingListFilter = .open
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var selected: BookingRequestItem? = nil
    @State private var showAnalytics = false
    @State private var showBookingPage = false

    init(businessID: UUID?) {
        self.businessID = businessID
    }

    // MARK: - Data

    private var searched: [BookingRequestItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return bookings }
        return bookings.filter {
            $0.customerName.lowercased().contains(q)
                || $0.serviceName.lowercased().contains(q)
                || ($0.clientEmail ?? "").lowercased().contains(q)
                || ($0.clientPhone ?? "").lowercased().contains(q)
        }
    }

    private var groups: [BookingGroup] {
        let items = searched
        let byStart: (BookingRequestItem, BookingRequestItem) -> Bool = {
            ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture)
        }
        let needsAnswer = items.filter { $0.stage == .needsAnswer }.sorted(by: byStart)
        let deposit = items.filter { $0.stage == .awaitingDeposit }.sorted(by: byStart)
        let confirmed = items.filter { $0.stage == .confirmed }
        let upcoming = confirmed.filter { !$0.isPast() }.sorted(by: byStart)
        let past = confirmed.filter { $0.isPast() }.sorted { !byStart($0, $1) }
        let closed = items.filter { $0.stage == .declined || $0.stage == .canceled }
            .sorted { ($0.createdAtMs ?? 0) > ($1.createdAtMs ?? 0) }

        let all = [
            BookingGroup(title: "Needs your answer", bookings: needsAnswer),
            BookingGroup(title: "Waiting on deposit", bookings: deposit),
            BookingGroup(title: "Upcoming", bookings: upcoming),
            BookingGroup(title: "Past", bookings: past),
            BookingGroup(title: "Declined and canceled", bookings: closed),
        ]
        let wanted: Set<String>
        switch filter {
        case .open: wanted = ["Needs your answer", "Waiting on deposit"]
        case .upcoming: wanted = ["Upcoming"]
        case .past: wanted = ["Past"]
        case .declined: wanted = ["Declined and canceled"]
        case .all: wanted = Set(all.map(\.title))
        }
        return all.filter { wanted.contains($0.title) && !$0.bookings.isEmpty }
    }

    private func count(_ option: BookingListFilter) -> Int {
        switch option {
        case .open: return bookings.filter { $0.stage == .needsAnswer || $0.stage == .awaitingDeposit }.count
        case .upcoming: return bookings.filter { $0.stage == .confirmed && !$0.isPast() }.count
        default: return 0
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search name, service, email, phone", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)

                    SBWFilterChips(
                        options: BookingListFilter.allCases,
                        title: { option in
                            let n = count(option)
                            return n > 0 ? "\(option.rawValue) \(n)" : option.rawValue
                        },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if businessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to see its bookings.")
                    )
                } else if isLoading && bookings.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading bookings…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if groups.isEmpty {
                    Section { emptyState }
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.bookings) { booking in
                                Button {
                                    selected = booking
                                } label: {
                                    BookingListRow(booking: booking)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Bookings")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showBookingPage = true } label: {
                        Label("Your Booking Page", systemImage: "link")
                    }
                    Button { showAnalytics = true } label: {
                        Label("Booking Stats", systemImage: "chart.bar.xaxis")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .navigationDestination(item: $selected) { booking in
            BookingDetailView(request: booking) { updated in
                if let index = bookings.firstIndex(where: { $0.requestId == updated.requestId }) {
                    bookings[index] = updated
                }
            }
        }
        .navigationDestination(isPresented: $showAnalytics) {
            BookingAnalyticsView(businessID: businessID)
        }
        .navigationDestination(isPresented: $showBookingPage) {
            BookingPageView()
        }
        .task(id: businessID) { await load() }
        .refreshable { await load() }
        .alert("Couldn’t Load Bookings", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("Try Again") { Task { await load() } }
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.secondary)
            if isSearching {
                Text("No bookings match \"\(searchText)\"")
                    .font(.headline)
            } else if bookings.isEmpty {
                Text("No booking requests yet")
                    .font(.headline)
                Text("Share your booking page and requests show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button { showBookingPage = true } label: { Label("Your Booking Page", systemImage: "link") }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            } else {
                Text(filter == .open ? "Nothing waiting on you" : "No \(filter.rawValue.lowercased()) bookings")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Load

    private func load() async {
        guard let businessID else {
            bookings = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await PortalBackend.shared.fetchBookingRequests(businessId: businessID)
            bookings = dtos.map(BookingRequestItem.init(dto:))
            // A booking confirmed since the last look (its deposit paid, say)
            // gets its client and job; once only, see BookingWorkSetup.
            for booking in bookings where booking.stage == .confirmed && !booking.isPast() {
                await BookingWorkSetup.ensureJob(for: booking, businessID: businessID, context: modelContext)
            }
        } catch {
            if !(error is CancellationError) {
                loadError = error.localizedDescription
            }
        }
    }
}

private struct BookingListRow: View {
    let booking: BookingRequestItem

    private var detail: String {
        var parts = [booking.serviceName]
        if let start = booking.start {
            var time = start.formatted(date: .omitted, time: .shortened)
            if let end = booking.end { time += "–" + end.formatted(date: .omitted, time: .shortened) }
            parts.append(time)
        }
        switch booking.stage {
        case .awaitingDeposit:
            if let cents = booking.depositAmountCents, cents > 0 {
                parts.append("\(InvoicePaymentService.currency(cents)) deposit")
            }
        case .confirmed:
            if booking.depositPaid { parts.append("deposit paid") }
        default:
            break
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(booking.start.map { $0.formatted(.dateTime.month(.abbreviated)).uppercased() } ?? "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(booking.start.map { $0.formatted(.dateTime.day()) } ?? "")
                    .font(.title3.weight(.semibold))
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(booking.customerName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(booking.stage.label)
                .font(.caption2.weight(.semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(booking.stage.foreground.opacity(0.15)))
                .foregroundStyle(booking.stage.foreground)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension BookingListView: Equatable {
    static func == (lhs: BookingListView, rhs: BookingListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
