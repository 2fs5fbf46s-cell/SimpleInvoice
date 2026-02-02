import SwiftUI
import SwiftData

struct DashboardView: View {
    // Pull business profile for name + logo
    @Query private var profiles: [BusinessProfile]

    // Pull invoices for stats
    @Query private var invoices: [Invoice]
    @Query(sort: \Booking.startDate, order: .forward)
    private var bookings: [Booking]

    // MARK: - Computed: Profile
    private var profileName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Welcome" : name
    }

    private var logoImage: UIImage? {
        guard let data = profiles.first?.logoData else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Computed: Stats
    private var weekPaidTotal: Double {
        let start = Calendar.current.startOfWeek(for: Date())
        return invoices
            .filter { $0.isPaid && $0.issueDate >= start }
            .reduce(0) { $0 + $1.total }
    }

    private var monthPaidTotal: Double {
        let start = Calendar.current.startOfMonth(for: Date())
        return invoices
            .filter { $0.isPaid && $0.issueDate >= start }
            .reduce(0) { $0 + $1.total }
    }

    private var upcomingBookingsCount: Int {
        let now = Date()
        return bookings.filter { $0.endDate >= now && $0.status != "canceled" }.count
    }

    // MARK: - Layout
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            // Base background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // ✅ Option A: subtle header wash
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profileName)
                                .font(.system(size: 28, weight: .bold))

                            Text("Dashboard")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Logo in top-right
                        Group {
                            if let logoImage {
                                Image(uiImage: logoImage)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "briefcase.fill")
                                    .imageScale(.large)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SBWTheme.cardStroke, lineWidth: 1)
                        )
                    }
                    .padding(.top, 6)

                    // Stats strip
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Weekly",
                            value: currency(weekPaidTotal),
                            subtitle: "Paid"
                        )

                        StatCard(
                            title: "Monthly",
                            value: currency(monthPaidTotal),
                            subtitle: "Paid"
                        )

                        StatCard(
                            title: "Schedule",
                            value: "\(upcomingBookingsCount)",
                            subtitle: "Upcoming"
                        )
                    }

                    // Date row
                    HStack {
                        Text(formattedDate(Date()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formattedTime(Date()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)

                    // Main tiles grid
                    LazyVGrid(columns: columns, spacing: 12) {

                        NavigationLink { InvoiceListView() } label: {
                            TileCard(
                                title: "Invoices",
                                subtitle: "View & send",
                                systemImage: "doc.plaintext",
                                tint: .blue
                            )
                        }

                        NavigationLink { BookingsListView() } label: {
                            TileCard(
                                title: "Bookings",
                                subtitle: "Schedule",
                                systemImage: "calendar.badge.clock",
                                tint: .blue
                            )
                        }

                        NavigationLink { EstimateListView() } label: {
                            TileCard(
                                title: "Estimates",
                                subtitle: "Quotes",
                                systemImage: "doc.text.magnifyingglass",
                                tint: .green
                            )
                        }

                        NavigationLink { ClientListView() } label: {
                            TileCard(
                                title: "Customers",
                                subtitle: "Clients",
                                systemImage: "person.2",
                                tint: .green
                            )
                        }

                        NavigationLink { PortalDirectoryLauncherView() } label: {
                            TileCard(
                                title: "Client Portal",
                                subtitle: "Directory",
                                systemImage: "rectangle.portrait.and.arrow.right",
                                tint: .gradient
                            )
                        }

                        NavigationLink { JobsListView() } label: {
                            TileCard(
                                title: "Requests",
                                subtitle: "Jobs",
                                systemImage: "tray.full",
                                tint: .gradient
                            )
                        }

                        NavigationLink { ContractsHomeView() } label: {
                            TileCard(
                                title: "Contracts",
                                subtitle: "View & send",
                                systemImage: "doc.text",
                                tint: .mint
                            )
                        }

                        NavigationLink { SavedItemsView() } label: {
                            TileCard(
                                title: "Inventory",
                                subtitle: "Saved items",
                                systemImage: "tag",
                                tint: .mint
                            )
                        }
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("") // Keep header custom
        .settingsGear { BusinessProfileView() }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers
    private func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d yyyy"
        return f.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Tile Card

private struct TileCard: View {
    enum Tint {
        case blue, green, gradient
        case teal, indigo, orange, purple, mint
        case neutral
    }

    

    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Tint

    private var wash: LinearGradient {
        switch tint {
        case .blue:
            return LinearGradient(
                colors: [SBWTheme.brandBlue.opacity(0.14), SBWTheme.brandBlue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .green:
            return LinearGradient(
                colors: [SBWTheme.brandGreen.opacity(0.14), SBWTheme.brandGreen.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gradient:
            return LinearGradient(
                colors: [SBWTheme.brandBlue.opacity(0.12), SBWTheme.brandGreen.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .teal:
            return LinearGradient(
                colors: [Color.teal.opacity(0.14), Color.teal.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .indigo:
            return LinearGradient(
                colors: [Color.indigo.opacity(0.14), Color.indigo.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .orange:
            return LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .purple:
            return LinearGradient(
                colors: [Color.purple.opacity(0.14), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mint:
            return LinearGradient(
                colors: [Color.mint.opacity(0.14), Color.mint.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .neutral:
            return LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    private var iconChip: AnyShapeStyle {
        switch tint {
        case .blue:     return AnyShapeStyle(SBWTheme.blueTint)
        case .green:    return AnyShapeStyle(SBWTheme.greenTint)
        case .gradient: return AnyShapeStyle(SBWTheme.brandGradient.opacity(0.20))

        case .teal:     return AnyShapeStyle(Color.teal.opacity(0.18))
        case .indigo:   return AnyShapeStyle(Color.indigo.opacity(0.18))
        case .orange:   return AnyShapeStyle(Color.orange.opacity(0.18))
        case .purple:   return AnyShapeStyle(Color.purple.opacity(0.18))
        case .mint:     return AnyShapeStyle(Color.mint.opacity(0.18))

        case .neutral:  return AnyShapeStyle(Color.black.opacity(0.06))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconChip)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 34, height: 34)

                Spacer()
            }

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(height: 112)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))

                // ✅ subtle gradient wash inside the tile
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(wash)
                    .blendMode(.normal)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ✅ Accent strip
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(SBWTheme.statAccent(for: title))
                .frame(width: 28, height: 4)
                .padding(.top, 2)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }

    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
