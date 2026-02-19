import SwiftUI
import SwiftData
import Charts

struct BookingAnalyticsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Query private var jobs: [Job]

    @State private var selectedRange: BookingAnalyticsRange = .days30
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String? = nil

    @State private var bookingRequests: [BookingRequestItem] = []
    @State private var snapshot: BookingAnalyticsSnapshot? = nil

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if isLoading && snapshot == nil {
                ProgressView("Loading booking analytics…")
                    .controlSize(.large)
            } else if let snapshot {
                ScrollView {
                    VStack(spacing: 16) {
                        rangeControl
                        kpiGrid(snapshot: snapshot)
                        trendCard(snapshot: snapshot)
                        funnelCard(snapshot: snapshot)
                        topServicesCard(snapshot: snapshot)
                        recentActivityCard(snapshot: snapshot)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await refreshFromServer()
                }
            } else {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Booking analytics will appear after booking activity is available.")
                )
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        Button("Retry") {
                            Task { await refreshFromServer() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("Booking Analytics")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        recomputeSnapshot()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task(id: activeBiz.activeBusinessID?.uuidString ?? "none") {
            guard !hasLoaded else { return }
            await refreshFromServer()
            hasLoaded = true
        }
        .onChange(of: selectedRange) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                recomputeSnapshot()
            }
        }
        .onChange(of: invoices.count) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                recomputeSnapshot()
            }
        }
        .alert("Booking Analytics Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private var rangeControl: some View {
        AnalyticsCard {
            Picker("Range", selection: $selectedRange) {
                ForEach(BookingAnalyticsRange.allCases) { range in
                    Text(range.shortLabel).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func kpiGrid(snapshot: BookingAnalyticsSnapshot) -> some View {
        let columns = [GridItem(.adaptive(minimum: 165, maximum: 280), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink {
                BookingAnalyticsDetailListView(
                    title: "All Requests",
                    bookings: snapshot.inRangeBookings,
                    range: snapshot.range,
                    filter: .all
                )
            } label: {
                kpiCard(
                    title: "Requests",
                    value: "\(snapshot.totalRequests)",
                    subtitle: snapshot.range.subtitle,
                    deltaText: deltaText(snapshot.delta?.requests)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                BookingAnalyticsDetailListView(
                    title: "Approved",
                    bookings: snapshot.inRangeBookings,
                    range: snapshot.range,
                    filter: .approved
                )
            } label: {
                kpiCard(
                    title: "Approved",
                    value: "\(snapshot.approvedCount)",
                    subtitle: snapshot.range.subtitle,
                    deltaText: deltaText(snapshot.delta?.approved)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                BookingAnalyticsDetailListView(
                    title: "Declined",
                    bookings: snapshot.inRangeBookings,
                    range: snapshot.range,
                    filter: .declined
                )
            } label: {
                kpiCard(
                    title: "Declined",
                    value: "\(snapshot.declinedCount)",
                    subtitle: snapshot.range.subtitle,
                    deltaText: deltaText(snapshot.delta?.declined)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                BookingAnalyticsDetailListView(
                    title: "Deposit Requested",
                    bookings: snapshot.inRangeBookings,
                    range: snapshot.range,
                    filter: .depositRequested
                )
            } label: {
                kpiCard(
                    title: "Deposit Requested",
                    value: "\(snapshot.depositRequestedCount)",
                    subtitle: snapshot.range.subtitle,
                    deltaText: deltaText(snapshot.delta?.depositRequested)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                BookingAnalyticsDetailListView(
                    title: "Deposits Paid",
                    bookings: snapshot.inRangeBookings,
                    range: snapshot.range,
                    filter: .depositPaid
                )
            } label: {
                kpiCard(
                    title: "Deposits Paid",
                    value: "\(snapshot.depositsPaidCount)",
                    subtitle: snapshot.range.subtitle,
                    deltaText: deltaText(snapshot.delta?.depositsPaid)
                )
            }
            .buttonStyle(.plain)

            kpiCard(
                title: "Conversion Rate",
                value: percent(snapshot.conversionRate),
                subtitle: "Approved / Requests",
                deltaText: nil
            )

            kpiCard(
                title: "Deposit Conversion",
                value: percent(snapshot.depositConversionRate),
                subtitle: "Deposits Paid / Requested",
                deltaText: nil
            )

            kpiCard(
                title: "Revenue",
                value: money(snapshot.totalRevenueCents),
                subtitle: snapshot.range.subtitle,
                deltaText: deltaMoneyText(snapshot.delta?.revenueCents)
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, deltaText: String?) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let deltaText {
                    Text(deltaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trendCard(snapshot: BookingAnalyticsSnapshot) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trend")
                    .font(.headline)

                if snapshot.trend.isEmpty {
                    Text("No trend data yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(snapshot.trend) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Requests", point.requests)
                        )
                        .foregroundStyle(SBWTheme.brandBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Requests", point.requests)
                        )
                        .foregroundStyle(SBWTheme.brandBlue.opacity(0.16))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Approved", point.approved)
                        )
                        .foregroundStyle(SBWTheme.brandGreen)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .frame(height: 220)
                    .chartLegend(position: .top, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: snapshot.trend)
                }
            }
        }
    }

    private func funnelCard(snapshot: BookingAnalyticsSnapshot) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Booking Funnel")
                    .font(.headline)

                ForEach(snapshot.funnel) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(row.count) • \(percent(row.ratio))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        ProgressView(value: max(0, min(1, row.ratio)))
                            .tint(colorForFunnelRow(row.id))
                    }
                }
            }
        }
    }

    private func topServicesCard(snapshot: BookingAnalyticsSnapshot) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Services")
                    .font(.headline)

                if snapshot.topServices.isEmpty {
                    Text("No services in this range.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.topServices) { service in
                        NavigationLink {
                            BookingAnalyticsDetailListView(
                                title: service.name,
                                bookings: snapshot.inRangeBookings,
                                range: snapshot.range,
                                filter: .serviceType(service.name)
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(service.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(service.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.08))
                                        Capsule()
                                            .fill(SBWTheme.brandGradient)
                                            .frame(width: max(8, geo.size.width * service.ratio))
                                    }
                                }
                                .frame(height: 8)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recentActivityCard(snapshot: BookingAnalyticsSnapshot) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Activity")
                    .font(.headline)

                if snapshot.recentActivity.isEmpty {
                    Text("No recent booking activity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.recentActivity.prefix(6)) { booking in
                        NavigationLink {
                            BookingDetailView(request: booking)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clientLabel(for: booking))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(BookingAnalyticsEngine.bookingDate(booking), style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusChip(booking.status)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MainActor
    private func refreshFromServer() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        } catch {
            // Keep non-fatal. The view still shows graceful empty state.
        }

        guard let businessId = activeBiz.activeBusinessID else {
            bookingRequests = []
            withAnimation(.easeInOut(duration: 0.25)) {
                snapshot = nil
            }
            return
        }

        do {
            let dtos = try await PortalBackend.shared.fetchBookingRequests(businessId: businessId)
            bookingRequests = dtos.map { dto in
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
                    bookingTotalAmountCents: dto.bookingTotalAmountCents,
                    depositAmountCents: dto.depositAmountCents,
                    depositInvoiceId: dto.depositInvoiceId,
                    depositPaidAtMs: dto.depositPaidAtMs,
                    finalInvoiceId: dto.finalInvoiceId
                )
            }
            errorMessage = nil
        } catch {
            bookingRequests = []
            errorMessage = error.localizedDescription
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            recomputeSnapshot()
        }
    }

    private func recomputeSnapshot() {
        guard let businessId = activeBiz.activeBusinessID else {
            snapshot = nil
            return
        }
        snapshot = BookingAnalyticsEngine.buildSnapshot(
            bookingRequests: bookingRequests,
            invoices: invoices,
            jobs: jobs,
            businessId: businessId,
            timeRange: selectedRange
        )
    }

    private func clientLabel(for booking: BookingRequestItem) -> String {
        if let name = booking.clientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = booking.clientEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return "Unknown client"
    }

    private func colorForFunnelRow(_ id: String) -> Color {
        switch id {
        case "requests":
            return SBWTheme.brandBlue
        case "deposit_requested":
            return Color.yellow
        case "deposits_paid":
            return SBWTheme.brandBlue
        case "approved":
            return SBWTheme.brandGreen
        default:
            return .secondary
        }
    }

    private func statusChip(_ rawStatus: String) -> some View {
        let normalized = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tuple: (label: String, fg: Color, bg: Color)

        if normalized == "approved" {
            tuple = ("APPROVED", SBWTheme.brandGreen, SBWTheme.brandGreen.opacity(0.12))
        } else if normalized == "declined" {
            tuple = ("DECLINED", .red, .red.opacity(0.12))
        } else if normalized == "deposit_requested" {
            tuple = ("DEPOSIT REQUESTED", .yellow, .yellow.opacity(0.14))
        } else if normalized == "deposit_paid" {
            tuple = ("DEPOSIT PAID", SBWTheme.brandBlue, SBWTheme.brandBlue.opacity(0.16))
        } else {
            tuple = ("PENDING", .orange, .orange.opacity(0.12))
        }

        return Text(tuple.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tuple.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tuple.bg)
            .clipShape(Capsule())
    }

    private func money(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        return value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    private func percent(_ value: Double) -> String {
        min(max(value, 0), 1).formatted(.percent.precision(.fractionLength(1)))
    }

    private func deltaText(_ delta: Int?) -> String? {
        guard let delta else { return nil }
        if delta == 0 { return "No change vs previous period" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta) vs previous period"
    }

    private func deltaMoneyText(_ delta: Int?) -> String? {
        guard let delta else { return nil }
        if delta == 0 { return "No change vs previous period" }
        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(money(abs(delta))) vs previous period"
    }
}

private struct AnalyticsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
            )
    }
}
