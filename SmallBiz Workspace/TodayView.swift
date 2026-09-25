import SwiftUI
import SwiftData
import UIKit

/// The day: what needs the owner, what's on the schedule, and three numbers.
///
/// Needs You rows each carry their next step as a button (Remind, Answer,
/// Bill…) and open the record when tapped. The week strip picks the day
/// shown under Today; the snapshot tiles open Money or Work. Setup steps
/// moved to the Business sheet, and the numbers come from MoneyMath so they
/// match Money and each client.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter
    @StateObject private var metricsVM = DashboardMetricsVM()

    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    /// Not read directly: the feed fetches contracts itself, but querying
    /// them here refreshes Today when one changes (signed, reminded).
    @Query private var contracts: [Contract]
    @Query private var profiles: [BusinessProfile]
    @Query(filter: #Predicate<AppNotification> { $0.readAtMs == nil }) private var unreadNotifications: [AppNotification]

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showNotifications = false
    @State private var selectedInvoice: Invoice?
    @State private var selectedContract: Contract?
    @State private var selectedJob: Job?
    @State private var selectedBooking: BookingRequestItem?
    @State private var pendingReminder: AttentionItem?
    @State private var working: String?
    @State private var notice: String?

    init(businessID: UUID? = nil) {
        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == scopedID })
        _jobs = Query(filter: #Predicate<Job> { $0.businessID == scopedID }, sort: [SortDescriptor(\Job.startDate)])
        _contracts = Query(filter: #Predicate<Contract> { $0.businessID == scopedID })
    }

    private var businessID: UUID? {
        BusinessScoped.effectiveBusinessID(explicit: nil, activeBusinessID: activeBiz.activeBusinessID)
    }

    private var unreadNotificationCount: Int {
        guard let businessID else { return 0 }
        return unreadNotifications.filter { $0.businessId == businessID }.count
    }

    /// Scheduled work: not canceled, not waiting for a date.
    private var scheduledJobs: [Job] {
        jobs.scoped(to: businessID).filter {
            let status = JobDisplayStatus($0)
            return status != .canceled && status != .needsScheduling
        }
    }

    private func jobs(on day: Date) -> [Job] {
        scheduledJobs.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
    }

    // Read once per body pass; the feed fetches from SwiftData.
    private var attentionItems: [AttentionItem] {
        AttentionFeedService.attentionItems(businessID: businessID, context: modelContext, remote: metricsVM.remote)
    }

    var body: some View {
        let items = attentionItems
        return ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if businessID == nil {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to see your day.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let notice { noticeBanner(notice) }

                        sectionLabel(items.isEmpty ? "Needs You" : "Needs You · \(items.count)")
                        needsYou(items)
                            .coachMark(id: "walkthrough.today.needsyou")

                        sectionLabel(dayTitle)
                        daySchedule

                        sectionLabel("This Week")
                        weekStrip

                        sectionLabel("Snapshot")
                        snapshot
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable { await refresh(force: true) }
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
                Button { showNotifications = true } label: {
                    Image(systemName: unreadNotificationCount > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(.multicolor)
                }
                .accessibilityLabel(unreadNotificationCount > 0 ? "Notifications, \(unreadNotificationCount) unread" : "Notifications")
            }
        }
        .navigationDestination(isPresented: $showNotifications) { NotificationsView() }
        .navigationDestination(item: $selectedInvoice) { InvoiceOverviewView(invoice: $0) }
        .navigationDestination(item: $selectedContract) { ContractDetailView(contract: $0) }
        .navigationDestination(item: $selectedJob) { JobDetailView(job: $0) }
        .navigationDestination(item: $selectedBooking) { booking in
            BookingDetailView(request: booking) { _ in Task { await refresh(force: true) } }
        }
        .confirmationDialog(
            reminderTitle,
            isPresented: Binding(get: { pendingReminder != nil }, set: { if !$0 { pendingReminder = nil } }),
            titleVisibility: .visible,
            presenting: pendingReminder
        ) { item in
            Button("Send Reminder") { Task { await sendReminder(item) } }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(reminderMessage(item))
        }
        .task(id: businessID) { await refresh(force: false) }
        .onAppear { Task { await refresh(force: false) } }
    }

    // MARK: - Header

    private var header: some View {
        let today = jobs(on: Calendar.current.startOfDay(for: .now)).count
        let dueThisWeek = MoneyMath.open(invoices).filter {
            $0.dueDate >= Calendar.current.startOfDay(for: .now) && $0.dueDate < Date.now.addingTimeInterval(7 * 86_400)
        }
        var parts: [String] = [today == 0 ? "No jobs today" : "\(today) job\(today == 1 ? "" : "s") today"]
        let due = dueThisWeek.reduce(0) { $0 + $1.balanceDueCents }
        if due > 0 { parts.append("\(InvoicePaymentService.currency(due)) due this week") }
        return VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.title2.weight(.bold))
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer()
            Button { notice = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.12)))
    }

    // MARK: - Needs You

    @ViewBuilder
    private func needsYou(_ items: [AttentionItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(SBWTheme.brandGreen)
                Text("You're all caught up").font(.headline)
                Text("Nothing needs you right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .todayCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 30) }
                    attentionRow(item)
                }
            }
            .todayCard()
        }
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 10) {
            Button { open(item) } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(item.severity))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if working == item.id {
                ProgressView().controlSize(.small)
            } else if item.severity == .critical {
                Button(item.action.title) { act(item) }
                    .sbwProminentButton()
                    .controlSize(.small)
            } else {
                Button(item.action.title) { act(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func color(_ severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return SBWTheme.brandBlue
        }
    }

    // MARK: - Day

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    @ViewBuilder
    private var daySchedule: some View {
        let dayJobs = jobs(on: selectedDay)
        if dayJobs.isEmpty {
            Text(Calendar.current.isDateInToday(selectedDay) ? "Nothing on the schedule today." : "Nothing scheduled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .todayCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(dayJobs.enumerated()), id: \.element.id) { index, job in
                    if index > 0 { Divider().padding(.leading, 66) }
                    dayRow(job)
                }
            }
            .todayCard()
        }
    }

    private func dayRow(_ job: Job) -> some View {
        let location = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = JobDisplayStatus(job)
        return HStack(spacing: 10) {
            Button { selectedJob = job } label: {
                HStack(spacing: 10) {
                    Text(job.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AttentionFeedService.jobName(job))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(location.isEmpty ? status.label : "\(location) · \(status.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !location.isEmpty,
               let url = URL(string: "http://maps.apple.com/?daddr=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Button { UIApplication.shared.open(url) } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Directions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Week

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDays, id: \.self) { day in
                let count = jobs(on: day).count
                let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                Button { selectedDay = day } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selected ? Color.white.opacity(0.9) : .secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selected ? .white : .primary)
                        HStack(spacing: 2) {
                            ForEach(0..<min(count, 3), id: \.self) { _ in
                                Circle().frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                        .foregroundStyle(selected ? .white : SBWTheme.brandBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month().day())), \(count) job\(count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: - Snapshot

    private var snapshot: some View {
        let received = MoneyMath.tally(MoneyMath.received(invoices: invoices, jobs: jobs), in: MoneyMath.lastDays(7))
        let owed = MoneyMath.owed(invoices)
        let week = weekDays.reduce(0) { $0 + jobs(on: $1).count }
        let unscheduled = jobs.scoped(to: businessID).filter { JobDisplayStatus($0) == .needsScheduling }.count
        return HStack(spacing: 8) {
            tile("In, 7 days", InvoicePaymentService.currency(received.cents),
                 "\(received.count) payment\(received.count == 1 ? "" : "s")") {
                MoneyHubView.show(.insights)
                AppRouteCenter.shared.route(.invoicesRoot)
            }
            tile("Owed to you", InvoicePaymentService.currency(owed.cents),
                 "\(owed.count) invoice\(owed.count == 1 ? "" : "s")") {
                MoneyHubView.show(.invoices)
                AppRouteCenter.shared.route(.invoicesRoot)
            }
            tile("Jobs this week", "\(week)", unscheduled > 0 ? "\(unscheduled) need a date" : "scheduled") {
                WorkHubView.show(.jobs)
                AppRouteCenter.shared.route(.workRoot)
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ value: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .todayCard(radius: 12)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.horizontal, 2)
            .padding(.top, 4)
    }

    // MARK: - Opening and acting

    private func open(_ item: AttentionItem) {
        switch item.kind {
        case .overdueInvoice(let id), .manualPayment(let id):
            selectedInvoice = fetch(Invoice.self, id)
        case .finishedJob(let id), .scheduleJob(let id):
            selectedJob = fetch(Job.self, id)
        case .contractWaiting(let id):
            selectedContract = fetch(Contract.self, id)
        case .bookingRequests(_, let first):
            if let first { selectedBooking = first } else { AppRouteCenter.shared.route(.bookingsRoot) }
        case .recurringWentOut:
            MoneyHubView.show(.invoices)
            AppRouteCenter.shared.route(.invoicesRoot)
        }
    }

    private func act(_ item: AttentionItem) {
        switch item.action {
        case .remind, .remindContract:
            pendingReminder = item
        case .answer, .confirm, .schedule:
            open(item)
        case .bill:
            guard case .finishedJob(let id) = item.kind, let job = fetch(Job.self, id) else { return }
            bill(job)
        case .gotIt:
            for invoice in invoices where invoice.isRecurringGenerated && invoice.recurringReviewedAt == nil {
                invoice.recurringReviewedAt = .now
            }
            try? modelContext.save()
        }
    }

    private func bill(_ job: Job) {
        let client = job.clientID.flatMap { id in
            try? modelContext.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })).first
        }
        let profile = profiles.first { $0.businessID == job.businessID }
        do {
            let invoice = try JobInvoiceBuilder.makeInvoice(for: job, client: client, profile: profile, context: modelContext)
            try? modelContext.save()
            selectedInvoice = invoice
        } catch {
            notice = "Couldn't make the invoice. Open the job to bill it."
        }
    }

    private var reminderTitle: String {
        if case .contractWaiting = pendingReminder?.kind { return "Remind them to sign?" }
        return "Send a payment reminder?"
    }

    private func reminderMessage(_ item: AttentionItem) -> String {
        switch item.kind {
        case .overdueInvoice(let id):
            guard let invoice = fetch(Invoice.self, id) else { return "" }
            return InvoiceSendService.confirmationMessage(for: invoice, kind: .reminder)
        case .contractWaiting(let id):
            guard let contract = fetch(Contract.self, id) else { return "" }
            return ContractSendService.confirmationMessage(for: contract, kind: .reminder)
        default:
            return ""
        }
    }

    @MainActor
    private func sendReminder(_ item: AttentionItem) async {
        working = item.id
        defer { working = nil }
        do {
            switch item.kind {
            case .overdueInvoice(let id):
                guard let invoice = fetch(Invoice.self, id) else { return }
                let name = profiles.first { $0.businessID == invoice.businessID }?.name
                switch try await InvoiceSendService.send(invoice, kind: .reminder, context: modelContext, businessName: name) {
                case .emailed(let to): notice = "Reminder sent to \(to)."
                case .publishedNotEmailed(_, let reason): notice = "The reminder didn't send: \(reason)"
                }
            case .contractWaiting(let id):
                guard let contract = fetch(Contract.self, id) else { return }
                switch try await ContractSendService.send(contract, kind: .reminder, context: modelContext) {
                case .emailed(let to): notice = "Reminder sent to \(to)."
                case .publishedNotEmailed(_, let reason): notice = "The reminder didn't send: \(reason)"
                }
            default:
                return
            }
            Haptics.success()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, _ id: UUID) -> T? where T: Identifiable, T.ID == UUID {
        (try? modelContext.fetch(FetchDescriptor<T>()))?.first { $0.id == id }
    }

    private func refresh(force: Bool) async {
        await metricsVM.refresh(
            invoices: invoices.scoped(to: businessID),
            jobs: jobs.scoped(to: businessID),
            businessID: businessID,
            forceRemote: force
        )
    }
}

private extension View {
    func todayCard(radius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
    }
}
