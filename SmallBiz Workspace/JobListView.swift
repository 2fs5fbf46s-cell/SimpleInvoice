import OSLog
//
//  JobsListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// The Work tab's job list, grouped the way the day actually goes: what
/// needs a date, what's underway, today, what's coming, and what's done.
///
/// It used to be one list sorted by start date, newest first — so next
/// month's job sat above today's — with the status buried in a subtitle and
/// a swipe that deleted a job (and orphaned its invoices) without asking.
struct JobsListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var jobs: [Job]
    @Query private var clients: [Client]

    @State private var searchText: String = ""
    @State private var selectedJob: Job? = nil
    @State private var filter: Filter = .active
    @State private var pendingDelete: Job? = nil

    @State private var showingNewJob = false
    @State private var newJobDraft: Job? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _jobs = Query(
                filter: #Predicate<Job> { job in
                    job.businessID == businessID
                },
                sort: [SortDescriptor(\Job.startDate, order: .forward)]
            )
            _clients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == businessID
                },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )
        } else {
            _jobs = Query(sort: [SortDescriptor(\Job.startDate, order: .forward)])
            _clients = Query(sort: [SortDescriptor(\Client.name, order: .forward)])
        }
    }

    private enum Filter: String, CaseIterable, Hashable {
        case active = "Active"
        case completed = "Completed"
        case canceled = "Canceled"
        case all = "All"
    }

    private struct JobGroup: Identifiable {
        let title: String
        let jobs: [Job]
        var id: String { title }
    }

    private var clientByID: [UUID: Client] {
        Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var searchedJobs: [Job] {
        let scoped = jobs.scoped(to: businessID)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { job in
            job.title.localizedCaseInsensitiveContains(query)
                || job.locationName.localizedCaseInsensitiveContains(query)
                || (clientName(for: job)?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var groups: [JobGroup] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let all = searchedJobs

        func status(_ job: Job) -> JobDisplayStatus { JobDisplayStatus(job) }
        let scheduled = all.filter { status($0) == .scheduled }

        let active: [JobGroup] = [
            JobGroup(title: "Needs scheduling", jobs: all.filter { status($0) == .needsScheduling }),
            JobGroup(title: "In progress", jobs: all.filter { status($0) == .inProgress }),
            JobGroup(title: "Today", jobs: scheduled.filter { $0.startDate >= startOfToday && $0.startDate < startOfTomorrow }),
            JobGroup(title: "Upcoming", jobs: scheduled.filter { $0.startDate >= startOfTomorrow }),
            JobGroup(title: "Missed start", jobs: scheduled.filter { $0.startDate < startOfToday }.reversed()),
        ]
        let completed = JobGroup(
            title: "Completed",
            jobs: all.filter { status($0) == .completed }
                .sorted { ($0.completedAt ?? $0.endDate) > ($1.completedAt ?? $1.endDate) }
        )
        let canceled = JobGroup(
            title: "Canceled",
            jobs: all.filter { status($0) == .canceled }
                .sorted { ($0.canceledAt ?? $0.startDate) > ($1.canceledAt ?? $1.startDate) }
        )

        let result: [JobGroup]
        switch filter {
        case .active: result = active
        case .completed: result = [completed]
        case .canceled: result = [canceled]
        case .all: result = active + [completed, canceled]
        }
        return result.filter { !$0.jobs.isEmpty }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search jobs, clients, places", text: $searchText)
                            .textInputAutocapitalization(.never)

                        Button {
                            Haptics.lightTap()
                            addJobAndOpenSheet()
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brand.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Job")
                    }
                    .padding(.vertical, 4)

                    SBWFilterChips(
                        options: Filter.allCases,
                        title: { $0.rawValue },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if groups.isEmpty {
                    Section {
                        emptyState
                    }
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.jobs) { job in
                                Button {
                                    selectedJob = job
                                } label: {
                                    JobListRow(job: job, clientName: clientName(for: job))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    stageSwipeAction(for: job)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = job
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $selectedJob) { job in
            JobSummaryView(job: job)
        }
        .confirmationDialog(
            "Delete \(pendingDelete.map(jobTitle) ?? "this job")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Job", role: .destructive) {
                if let job = pendingDelete { delete(job) }
                pendingDelete = nil
            }
            Button("Keep Job", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage(for: pendingDelete))
        }
        .sheet(isPresented: $showingNewJob, onDismiss: { discardEmptyDraft() }) {
            NavigationStack {
                if let newJobDraft {
                    // isDraft: nothing is provisioned or auto-saved until
                    // Done, like the Create menu's New Job.
                    JobDetailView(job: newJobDraft, isDraft: true)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    discardDraft()
                                    showingNewJob = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { saveNewJob() }
                                    .fontWeight(.semibold)
                                    .disabled(newJobDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                } else {
                    ProgressView("Loading…")
                }
            }
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? emptyTitle : "No jobs match \"\(searchText)\"")
                .font(.headline)
            if searchText.isEmpty && filter == .active {
                Text("New jobs and jobs from accepted estimates show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    addJobAndOpenSheet()
                } label: {
                    Label("New Job", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brand)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyTitle: String {
        switch filter {
        case .active: return "No active jobs"
        case .completed: return "No completed jobs"
        case .canceled: return "No canceled jobs"
        case .all: return "No jobs yet"
        }
    }

    @ViewBuilder
    private func stageSwipeAction(for job: Job) -> some View {
        switch JobDisplayStatus(job) {
        case .scheduled, .needsScheduling:
            Button {
                JobLifecycle.start(job)
                save()
                Haptics.success()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .tint(SBWTheme.brand)
        case .inProgress:
            Button {
                JobLifecycle.complete(job)
                save()
                Haptics.success()
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(SBWTheme.success)
        case .canceled:
            Button {
                JobLifecycle.reopen(job)
                save()
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(SBWTheme.brand)
        case .completed:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func clientName(for job: Job) -> String? {
        guard let id = job.clientID else { return nil }
        let name = clientByID[id]?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private func jobTitle(_ job: Job) -> String {
        let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "this job" : "\"\(title)\""
    }

    private func deleteMessage(for job: Job?) -> String {
        JobDeletion.impactMessage(for: job)
    }

    private func delete(_ job: Job) {
        let eventID = job.calendarEventId
        let jobID = job.id
        Task { try? await CalendarEventService.shared.removeEvent(identifier: eventID) }
        Task { try? await PortalBackend.shared.removeJobScheduleReminder(jobId: jobID) }
        modelContext.delete(job)
        save()
        Haptics.success()
    }

    private func save() {
        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save jobs: \(error)") }
    }

    // MARK: - New job

    private func addJobAndOpenSheet() {
        guard let bizID = businessID else {
            SBWLog.ui.problem("❌ No active business selected")
            return
        }
        let start = JobDetailView.defaultScheduleStart()
        let job = Job(
            businessID: bizID,
            startDate: start,
            endDate: start.addingTimeInterval(2 * 3600)
        )
        job.stage = .booked
        modelContext.insert(job)
        newJobDraft = job
        showingNewJob = true
    }

    private func saveNewJob() {
        guard let job = newJobDraft else { return }
        do {
            try modelContext.save()
            newJobDraft = nil
            searchText = ""
            showingNewJob = false
            Haptics.success()
            selectedJob = job
            syncAppointmentReminderIfNeeded(for: job)
        } catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to save new job: \(error)")
        }
    }

    /// A new job's draft screen is `isDraft: true` the whole time it's open,
    /// so `JobDetailView`'s own onDisappear sync never fires for it — this
    /// covers that one gap, at the exact moment the draft becomes real.
    private func syncAppointmentReminderIfNeeded(for job: Job) {
        let jobID = job.id
        let client = job.clientID.flatMap { clientByID[$0] }
        guard JobAppointmentReminderEligibility.isEligible(job: job, client: client), let client else { return }
        let title = job.title
        let startDate = job.startDate
        let clientEmail = client.email
        let clientName = client.name
        Task {
            try? await PortalBackend.shared.syncJobScheduleReminder(
                jobId: jobID,
                title: title,
                startDate: startDate,
                clientEmail: clientEmail,
                clientName: clientName
            )
        }
    }

    private func discardDraft() {
        guard let job = newJobDraft else { return }
        modelContext.delete(job)
        try? modelContext.save()
        newJobDraft = nil
    }

    /// Covers any way the sheet closes without Done.
    private func discardEmptyDraft() {
        guard let job = newJobDraft else { return }
        if job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discardDraft()
        } else {
            newJobDraft = nil
        }
    }
}

/// A date block, the job, who and where, and its status.
private struct JobListRow: View {
    let job: Job
    let clientName: String?

    private var status: JobDisplayStatus { JobDisplayStatus(job) }

    var body: some View {
        HStack(spacing: 12) {
            dateBlock
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled job" : job.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(status.label)
                .font(.caption2.weight(.semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(status.foreground.opacity(0.15)))
                .foregroundStyle(status.foreground)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let place = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [clientName, place.isEmpty ? nil : place].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var dateBlock: some View {
        switch status {
        case .needsScheduling:
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(SBWTheme.attention)
        case .inProgress:
            Image(systemName: "hammer.fill")
                .font(.title3)
                .foregroundStyle(SBWTheme.success)
        default:
            let date = status == .completed ? (job.completedAt ?? job.endDate) : job.startDate
            VStack(spacing: 1) {
                if Calendar.current.isDateInToday(date) && status == .scheduled {
                    Text(date.formatted(.dateTime.hour().minute()))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(date.formatted(.dateTime.day()))
                        .font(.headline)
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension JobsListView: Equatable {
    static func == (lhs: JobsListView, rhs: JobsListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
