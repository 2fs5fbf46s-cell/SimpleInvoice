import SwiftUI
import SwiftData

/// Replaces the old Dashboard tab. Where Dashboard was a board of tiles plus
/// a Quick Start card competing for the same "what do I do now" answer,
/// Today is one ranked feed: overdue invoices outrank bookings waiting on
/// you, which outrank contracts waiting on the client, which outrank an
/// unfinished setup step. Every card disappears once it's handled — nothing
/// here is decorative.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter
    @StateObject private var metricsVM = DashboardMetricsVM()

    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]

    @State private var quickStart = QuickStartChecklist()
    @State private var weeklyPaidText = "—"
    @State private var scheduleCount = 0
    @State private var showHelpCenter = false
    @State private var selectedInvoice: Invoice?
    @State private var selectedContract: Contract?

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
        BusinessScoped.effectiveBusinessID(explicit: nil, activeBusinessID: activeBiz.activeBusinessID)
    }

    private var currentProfile: BusinessProfile? {
        guard let bizID = effectiveBusinessID else { return profiles.first }
        return profiles.first(where: { $0.businessID == bizID }) ?? profiles.first
    }

    private var attentionItems: [AttentionItem] {
        AttentionFeedService.attentionItems(
            businessID: effectiveBusinessID,
            context: modelContext,
            checklist: quickStart,
            pendingApprovalBookingCount: metricsVM.pendingApprovalBookingCount
        )
    }

    private var upcomingWeek: [WeekDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let scopedJobs = jobs.scoped(to: effectiveBusinessID)

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let count = scopedJobs.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.count
            return WeekDay(date: day, hasActivity: count > 0)
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if effectiveBusinessID == nil {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to see what needs attention.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("Needs You")
                        attentionSection
                            .coachMark(id: "walkthrough.today.needsyou")

                        sectionLabel("This Week")
                        weekStrip

                        sectionLabel("Snapshot")
                        snapshotRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BusinessAvatarButton { businessSettingsPresenter.open() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelpCenter = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help & About")
            }
        }
        .navigationDestination(isPresented: $showHelpCenter) {
            HelpCenterView()
        }
        .navigationDestination(item: $selectedInvoice) { InvoiceOverviewView(invoice: $0) }
        .navigationDestination(item: $selectedContract) { ContractDetailView(contract: $0) }
        .task(id: effectiveBusinessID) {
            await recomputeMetrics()
        }
        .task(id: quickStartRefreshKey) {
            await refreshQuickStart()
        }
        .onChange(of: invoices.count) {
            Task { await recomputeMetrics() }
        }
        .onChange(of: jobs.count) {
            Task { await recomputeMetrics() }
        }
    }

    // MARK: - Needs You

    private var attentionSection: some View {
        Group {
            if attentionItems.isEmpty {
                caughtUpCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attentionItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        Button {
                            handleTap(item)
                        } label: {
                            attentionRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SBWTheme.cardStroke, lineWidth: 1)
                )
            }
        }
    }

    private var caughtUpCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.scaledSystem(size: 30, weight: .regular, relativeTo: .largeTitle))
                .foregroundStyle(SBWTheme.brandGreen)
            Text("You're all caught up")
                .font(.headline)
            Text("Nothing needs your attention right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor(for: item.severity))
                .frame(width: 3)
                .padding(.vertical, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accentColor(for: item.severity).opacity(0.14))
                Image(systemName: icon(for: item.kind))
                    .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(accentColor(for: item.severity))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.scaledSystem(size: 13.5, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.scaledSystem(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let amountText = item.amountText {
                Text(amountText)
                    .font(.scaledSystem(size: 13.5, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } else {
                Image(systemName: "chevron.right")
                    .font(.scaledSystem(size: 12, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func accentColor(for severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return SBWTheme.brandBlue
        }
    }

    private func icon(for kind: AttentionKind) -> String {
        switch kind {
        case .overdueInvoice: return "exclamationmark.circle"
        case .unsignedContract: return "signature"
        case .pendingBookings: return "calendar.badge.clock"
        case .recurringInvoicesReady: return "arrow.triangle.2.circlepath"
        case .setupStep: return "sparkles"
        }
    }

    private func handleTap(_ item: AttentionItem) {
        switch item.kind {
        case .overdueInvoice(let invoiceID):
            selectedInvoice = fetchInvoice(id: invoiceID)
        case .unsignedContract(let contractID):
            selectedContract = fetchContract(id: contractID)
        case .pendingBookings:
            AppRouteCenter.shared.route(.workRoot)
        case .recurringInvoicesReady:
            AppRouteCenter.shared.route(.invoicesRoot)
        case .setupStep(let step):
            AppRouteCenter.shared.route(step.route)
        }
    }

    private func fetchInvoice(id: UUID) -> Invoice? {
        var descriptor = FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchContract(id: UUID) -> Contract? {
        var descriptor = FetchDescriptor<Contract>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - This Week

    private struct WeekDay: Identifiable {
        let date: Date
        let hasActivity: Bool
        var id: Date { date }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(upcomingWeek) { day in
                VStack(spacing: 4) {
                    Text(Self.weekdayFormatter.string(from: day.date).uppercased())
                        .font(.scaledSystem(size: 9, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                    Text(Self.dayNumberFormatter.string(from: day.date))
                        .font(.scaledSystem(size: 13, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(day.hasActivity ? SBWTheme.brandBlue : .primary)
                    Circle()
                        .fill(day.hasActivity ? SBWTheme.brandBlue : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SBWTheme.cardStroke, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Snapshot

    private var snapshotRow: some View {
        HStack(spacing: 10) {
            statCard(label: "Paid, 7 Days", value: weeklyPaidText)
            statCard(label: "Scheduled", value: "\(scheduleCount)")
        }
        .padding(.bottom, 8)
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.scaledSystem(size: 10.5, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.scaledSystem(size: 19, weight: .bold, relativeTo: .title3))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.scaledSystem(size: 10.5, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.horizontal, 2)
            .padding(.top, 4)
    }

    // MARK: - Data refresh

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

    private func recomputeMetrics() async {
        guard let businessID = effectiveBusinessID else {
            weeklyPaidText = "—"
            scheduleCount = 0
            return
        }

        let scopedInvoices = invoices.scoped(to: businessID)
        let scopedJobs = jobs.scoped(to: businessID)

        await metricsVM.refresh(
            invoices: scopedInvoices,
            jobs: scopedJobs,
            businessID: businessID,
            forceRemote: false
        )

        weeklyPaidText = Self.currencyFormatter.string(
            from: NSNumber(value: Double(metricsVM.weeklyPaidCents) / 100.0)
        ) ?? "$0.00"
        scheduleCount = metricsVM.scheduleCount
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}
