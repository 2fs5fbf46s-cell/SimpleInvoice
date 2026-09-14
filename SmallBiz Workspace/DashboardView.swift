import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @StateObject private var metricsVM = DashboardMetricsVM()
    @State private var metricState = DashboardMetricState()
    @State private var showHelpCenter = false
    @State private var quickStart = QuickStartChecklist()
    @State private var syncHealth = PortalSyncHealth.healthy
    @State private var isRetryingSync = false

    // Pull business profile for name + logo. One row per business, so this one
    // stays unfiltered — the whole table is a handful of records.
    @Query private var profiles: [BusinessProfile]

    // Stats for the active business only. These grow with use, so they are
    // filtered in the fetch rather than loaded whole and filtered in memory.
    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]

    init(businessID: UUID? = nil) {
        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _invoices = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.businessID == scopedID
            }
        )
        _jobs = Query(
            filter: #Predicate<Job> { job in
                job.businessID == scopedID
            },
            sort: [SortDescriptor(\Job.startDate, order: .forward)]
        )
    }

    private var effectiveBusinessID: UUID? {
        BusinessScoped.effectiveBusinessID(
            explicit: nil,
            activeBusinessID: activeBiz.activeBusinessID
        )
    }

    private struct DashboardMetricState: Equatable {
        let effectiveBusinessID: UUID?
        let weeklyPaidText: String
        let monthlyPaidText: String
        let scheduleText: String
        let isLoading: Bool

        static let placeholderText = "—"

        init(
            effectiveBusinessID: UUID? = nil,
            weeklyPaidText: String = placeholderText,
            monthlyPaidText: String = placeholderText,
            scheduleText: String = placeholderText,
            isLoading: Bool = false
        ) {
            self.effectiveBusinessID = effectiveBusinessID
            self.weeklyPaidText = weeklyPaidText
            self.monthlyPaidText = monthlyPaidText
            self.scheduleText = scheduleText
            self.isLoading = isLoading
        }

        static var noBusiness: DashboardMetricState {
            DashboardMetricState(isLoading: false)
        }
    }

    // MARK: - Computed: Profile
    private var currentProfile: BusinessProfile? {
        guard let bizID = activeBiz.activeBusinessID else { return profiles.first }
        return profiles.first(where: { $0.businessID == bizID }) ?? profiles.first
    }

    private var profileName: String {
        let name = currentProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Welcome" : name
    }

    private var logoImage: UIImage? {
        guard let data = currentProfile?.logoData else { return nil }
        return UIImage(data: data)
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
                                .font(.scaledSystem(size: 28, weight: .bold, relativeTo: .title))

                            Text("Dashboard")
                                .font(.scaledSystem(size: 16, weight: .semibold, relativeTo: .body))
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

                    if syncHealth.hasFailures, effectiveBusinessID != nil {
                        PortalSyncHealthCard(
                            health: syncHealth,
                            isRetrying: isRetryingSync,
                            retry: { Task { await retrySync() } }
                        )
                    }

                    if !quickStart.isFullyComplete, effectiveBusinessID != nil {
                        QuickStartDashboardCard(checklist: quickStart)
                    }

                    if effectiveBusinessID == nil {
                        ContentUnavailableView(
                            "No Business Selected",
                            systemImage: "building.2",
                            description: Text("Select a business to view dashboard metrics.")
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 30)
                    } else {
                        // Stats strip
                        HStack(spacing: 12) {
                            DashboardStatCard(
                                title: "Weekly",
                                value: metricState.weeklyPaidText,
                                subtitle: "Paid",
                                isLoading: metricState.isLoading
                            )

                            DashboardStatCard(
                                title: "Monthly",
                                value: metricState.monthlyPaidText,
                                subtitle: "Paid",
                                isLoading: metricState.isLoading
                            )

                            DashboardStatCard(
                                title: "Schedule",
                                value: metricState.scheduleText,
                                subtitle: "Upcoming",
                                isLoading: metricState.isLoading
                            )
                        }
                        .coachMark(id: "walkthrough.dashboard.metrics")
                        .animation(.easeInOut(duration: 0.18), value: metricState)

                        // Date row (live)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            let now = context.date
                            HStack {
                                Text(formattedDate(now))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(formattedTime(now))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }

                        // Main tiles grid
                        LazyVGrid(columns: columns, spacing: 12) {

                            NavigationLink { InvoiceListView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Invoices",
                                    subtitle: "View & send",
                                    systemImage: "doc.plaintext",
                                    tint: .blue
                                )
                            }

                            NavigationLink { BookingsListView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Bookings",
                                    subtitle: "Schedule",
                                    systemImage: "calendar.badge.clock",
                                    tint: .blue
                                )
                            }

                            NavigationLink { EstimateListView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Estimates",
                                    subtitle: "Quotes",
                                    systemImage: "doc.text.magnifyingglass",
                                    tint: .green
                                )
                            }

                            NavigationLink { ClientListView(businessID: effectiveBusinessID) } label: {
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

                            NavigationLink { JobsListView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Jobs",
                                    subtitle: "Projects",
                                    systemImage: "tray.full",
                                    tint: .gradient
                                )
                            }

                            NavigationLink { ContractsHomeView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Contracts",
                                    subtitle: "View & send",
                                    systemImage: "doc.text",
                                    tint: .mint
                                )
                            }

                            NavigationLink { SavedItemsView(businessID: effectiveBusinessID) } label: {
                                TileCard(
                                    title: "Inventory",
                                    subtitle: "Services & materials",
                                    systemImage: "tag",
                                    tint: .mint
                                )
                            }
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelpCenter = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help Center")
            }
        }
        .navigationDestination(isPresented: $showHelpCenter) {
            HelpCenterView()
        }
        .task(id: effectiveBusinessID) {
            await recomputeDashboardMetrics(forceRemote: false)
        }
        .task(id: quickStartRefreshKey) { await refreshQuickStart() }
        .task(id: quickStartRefreshKey) { refreshSyncHealth() }
        .onChange(of: invoices.count) {
            Task {
                await recomputeDashboardMetrics(forceRemote: false)
            }
        }
        .onChange(of: jobs.count) {
            Task {
                await recomputeDashboardMetrics(forceRemote: false)
            }
        }
    }

    // MARK: - Helpers
    private func recomputeDashboardMetrics(forceRemote: Bool) async {
        guard let businessID = effectiveBusinessID else {
            metricState = .noBusiness
            return
        }

        if metricState.effectiveBusinessID == businessID {
            metricState = DashboardMetricState(
                effectiveBusinessID: businessID,
                weeklyPaidText: metricState.weeklyPaidText,
                monthlyPaidText: metricState.monthlyPaidText,
                scheduleText: metricState.scheduleText,
                isLoading: true
            )
        } else {
            metricState = DashboardMetricState(
                effectiveBusinessID: businessID,
                isLoading: true,
            )
        }

        let scopedInvoices = invoices.scoped(to: businessID)
        let scopedJobs = jobs.scoped(to: businessID)

        await metricsVM.refresh(
            invoices: scopedInvoices,
            jobs: scopedJobs,
            businessID: businessID,
            forceRemote: forceRemote
        )

        metricState = DashboardMetricState(
            effectiveBusinessID: businessID,
            weeklyPaidText: formatCurrency(cents: metricsVM.weeklyPaidCents),
            monthlyPaidText: formatCurrency(cents: metricsVM.monthlyPaidCents),
            scheduleText: "\(metricsVM.scheduleCount)",
            isLoading: false
        )
    }

    private func formatCurrency(cents: Int) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// Re-derives when the business changes or the data behind a step moves.
    private var quickStartRefreshKey: String {
        "\(effectiveBusinessID?.uuidString ?? "none")-\(invoices.count)"
    }

    @MainActor
    private func refreshQuickStart() async {
        let status = await NotificationManager().getAuthorizationStatus()
        quickStart = QuickStartChecklist.fromStoredData(
            businessID: effectiveBusinessID,
            context: modelContext,
            notificationsEnabled: QuickStartChecklist.notificationsAreEnabled(status: status)
        )
    }


    @MainActor
    private func refreshSyncHealth() {
        syncHealth = PortalSyncHealth.current(
            businessID: effectiveBusinessID,
            context: modelContext
        )
    }

    /// Retry every document that failed, rather than making the user open each one.
    @MainActor
    private func retrySync() async {
        guard !isRetryingSync, let businessID = effectiveBusinessID else { return }
        isRetryingSync = true
        defer { isRetryingSync = false }

        let invoiceIDs = ((try? modelContext.fetch(
            FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { $0.businessID == businessID && $0.portalNeedsUpload }
            )
        )) ?? []).map(\.id)

        let contractIDs = ((try? modelContext.fetch(
            FetchDescriptor<Contract>(
                predicate: #Predicate<Contract> { $0.businessID == businessID && $0.portalNeedsUpload }
            )
        )) ?? []).map(\.id)

        for id in invoiceIDs {
            _ = await PortalAutoSyncService.uploadInvoice(invoiceId: id, context: modelContext)
        }
        for id in contractIDs {
            _ = await PortalAutoSyncService.uploadContract(contractId: id, context: modelContext)
        }

        refreshSyncHealth()
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
                        .font(.scaledSystem(size: 18, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                }
                .frame(width: 34, height: 34)

                Spacer()
            }

            Text(title)
                .font(.scaledSystem(size: 16, weight: .bold, relativeTo: .body))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.scaledSystem(size: 13, weight: .semibold, relativeTo: .footnote))
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
                .font(.scaledSystem(size: 12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.scaledSystem(size: 16, weight: .bold, relativeTo: .body))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())

            Text(subtitle)
                .font(.scaledSystem(size: 12, weight: .semibold, relativeTo: .caption))
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

// MARK: - Dashboard Stat Wrapper

private struct DashboardStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let isLoading: Bool

    var body: some View {
        StatCard(title: title, value: value, subtitle: subtitle)
            .redacted(reason: isLoading ? .placeholder : [])
            .opacity(isLoading ? 0.7 : 1)
    }
}



/// Entry point to Quick Start from the dashboard.
///
/// The checklist was previously reachable only through More -> Help Center ->
/// Quick Start, three taps from a dashboard that never mentioned it.
private struct QuickStartDashboardCard: View {
    let checklist: QuickStartChecklist

    var body: some View {
        NavigationLink {
            QuickStartView()
        } label: {
            SBWCardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    QuickStartProgressHeader(checklist: checklist)

                    if let next = checklist.nextStep {
                        HStack(spacing: 6) {
                            Text("Next: \(next.title)")
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SBWTheme.brandBlue)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Start, \(checklist.completedCount) of \(checklist.totalCount) steps complete")
        .accessibilityHint(checklist.nextStep.map { "Next: \($0.title)" } ?? "")
    }
}


/// Account-level sync status.
///
/// Sits above Quick Start because a document that failed to reach a client is
/// more urgent than a setup step, and disappears entirely when nothing has failed.
private struct PortalSyncHealthCard: View {
    let health: PortalSyncHealth
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(health.summary)
                        .font(.headline)
                    Spacer(minLength: 8)
                }

                if let message = health.latestMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: retry) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView().controlSize(.small)
                        }
                        Text(isRetrying ? "Retrying…" : "Retry all")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .disabled(isRetrying)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(health.summary)
        .accessibilityHint("Retries sending them to your clients")
    }
}
