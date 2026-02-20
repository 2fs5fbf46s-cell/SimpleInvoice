//
//  JobsListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct JobsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)])
    private var jobs: [Job]
    @Query private var clients: [Client]

    @State private var searchText: String = ""
    @State private var selectedJob: Job? = nil
    @State private var filter: Filter = .all

    // ✅ New Job sheet (Clients-style)
    @State private var showingNewJob = false
    @State private var newJobDraft: Job? = nil

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case booked = "Booked"
        case inProgress = "In Progress"
        case completed = "Completed"
        case canceled = "Canceled"

        var id: String { rawValue }
    }

    // MARK: - Scoped jobs (active business)

    private var scopedJobs: [Job] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return jobs.filter { $0.businessID == bizID }
    }

    private var filteredJobs: [Job] {
        let byFilter: [Job]
        switch filter {
        case .all:
            byFilter = scopedJobs
        case .booked:
            byFilter = scopedJobs.filter { resolvedFilter(for: $0) == .booked }
        case .inProgress:
            byFilter = scopedJobs.filter { resolvedFilter(for: $0) == .inProgress }
        case .completed:
            byFilter = scopedJobs.filter { resolvedFilter(for: $0) == .completed }
        case .canceled:
            byFilter = scopedJobs.filter { resolvedFilter(for: $0) == .canceled }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return byFilter }

        return byFilter.filter { job in
            if job.title.localizedCaseInsensitiveContains(query) { return true }
            if let clientName = clientName(for: job),
               clientName.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if activeBiz.activeBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view jobs.")
                    )
                } else if filteredJobs.isEmpty {
                    ContentUnavailableView(
                        scopedJobs.isEmpty ? "No Jobs Yet" : "No Results",
                        systemImage: "briefcase",
                        description: Text(scopedJobs.isEmpty
                                          ? "Tap + to create your first job."
                                          : "Try a different filter or search term.")
                    )
                } else {
                    ForEach(filteredJobs) { job in
                        Button {
                            selectedJob = job
                        } label: {
                            jobRow(job)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteJobs)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search jobs"
        )
        .navigationDestination(item: $selectedJob) { job in
            JobDetailView(job: job)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { addJobAndOpenSheet() } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewJob, onDismiss: { newJobDraft = nil }) {
            NavigationStack {
                if let newJobDraft {
                    JobDetailView(job: newJobDraft)
                        .navigationTitle("New Job")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { deleteIfEmptyAndClose() }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    if newJobDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        deleteIfEmptyAndClose()
                                        return
                                    }

                                    do {
                                        try modelContext.save()
                                        searchText = ""
                                        showingNewJob = false
                                    } catch {
                                        print("Failed to save new job: \(error)")
                                    }
                                }
                            }
                        }
                } else {
                    ProgressView("Loading…")
                        .navigationTitle("New Job")
                }
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Row UI (Option A polish parity)

    private func jobRow(_ job: Job) -> some View {
        let contractCount = job.contracts?.count ?? 0

        let statusText = normalizedJobStatusLabel(for: resolvedFilter(for: job))
        let location = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = job.startDate.formatted(date: .abbreviated, time: .omitted)
        let clientText = clientName(for: job)
        let contractText = contractCount > 0 ? "\(contractCount) contract\(contractCount == 1 ? "" : "s")" : nil
        let subtitle = [statusText, clientText, location.isEmpty ? nil : location, contractText, date]
            .compactMap { $0 }
            .joined(separator: " • ")

        return HStack(alignment: .top, spacing: 12) {

            // Leading icon chip (matches Contracts/Invoices/Bookings)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Jobs"))
                Image(systemName: "tray.full")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(
                title: job.title.isEmpty ? "Job" : job.title,
                subtitle: subtitle.isEmpty ? " " : subtitle
            )
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private func normalizedJobStatusLabel(for filter: Filter) -> String {
        switch filter {
        case .booked:
            return "SCHEDULED"
        case .inProgress:
            return "IN PROGRESS"
        case .completed:
            return "COMPLETED"
        case .canceled:
            return "CANCELED"
        case .all:
            return "SCHEDULED"
        }
    }

    // MARK: - Add / Delete

    private func addJobAndOpenSheet() {
        guard let bizID = activeBiz.activeBusinessID else {
            print("❌ No active business selected")
            return
        }

        let job = Job(
            businessID: bizID,
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )

        job.title = ""
        job.status = "scheduled"
        job.stage = .booked

        modelContext.insert(job)
        newJobDraft = job
        showingNewJob = true

        do { try modelContext.save() }
        catch { print("Failed to save new job draft: \(error)") }
    }

    private func deleteIfEmptyAndClose() {
        guard let job = newJobDraft else {
            showingNewJob = false
            return
        }

        if job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelContext.delete(job)
        }

        do { try modelContext.save() }
        catch { print("Failed to save after cancel: \(error)") }

        showingNewJob = false
    }

    private func deleteJobs(at offsets: IndexSet) {
        let toDelete: [Job] = offsets.compactMap { idx -> Job? in
            guard idx < filteredJobs.count else { return nil }
            return filteredJobs[idx]
        }

        for job in toDelete {
            modelContext.delete(job)
        }

        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }

    private func resolvedFilter(for job: Job) -> Filter {
        let rawStage = job.stageRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rawStage == JobStage.booked.rawValue.lowercased() { return .booked }
        if rawStage == JobStage.inProgress.rawValue.lowercased() { return .inProgress }
        if rawStage == JobStage.completed.rawValue.lowercased() { return .completed }
        if rawStage == JobStage.canceled.rawValue.lowercased() { return .canceled }

        let status = job.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "booked" || status == "scheduled" { return .booked }
        if status == "in_progress" || status == "in progress" { return .inProgress }
        if status == "completed" { return .completed }
        if status == "canceled" || status == "cancelled" { return .canceled }
        return .booked
    }

    private func clientName(for job: Job) -> String? {
        guard let clientID = job.clientID else { return nil }
        let name = clients.first(where: { $0.id == clientID })?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return nil
    }
}
