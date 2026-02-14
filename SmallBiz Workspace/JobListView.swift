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

    @State private var searchText: String = ""
    @State private var selectedJob: Job? = nil

    // ✅ New Job sheet (Clients-style)
    @State private var showingNewJob = false
    @State private var newJobDraft: Job? = nil

    // MARK: - Scoped jobs (active business)

    private var scopedJobs: [Job] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return jobs.filter { $0.businessID == bizID }
    }

    private var searchedJobs: [Job] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matchesSearch(_ job: Job) -> Bool {
            guard !q.isEmpty else { return true }
            return job.title.lowercased().contains(q)
            || job.notes.lowercased().contains(q)
            || job.locationName.lowercased().contains(q)
            || job.status.lowercased().contains(q)
        }

        return scopedJobs.filter { matchesSearch($0) }
    }

    private var bookedJobs: [Job] {
        searchedJobs.filter { $0.stage == .booked }
    }

    private var inProgressJobs: [Job] {
        searchedJobs.filter { $0.stage == .inProgress }
    }

    private var completedJobs: [Job] {
        searchedJobs.filter { $0.stage == .completed }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                if bookedJobs.isEmpty && inProgressJobs.isEmpty && completedJobs.isEmpty {
                    ContentUnavailableView(
                        scopedJobs.isEmpty ? "No Jobs Yet" : "No Results",
                        systemImage: "briefcase",
                        description: Text(scopedJobs.isEmpty
                                          ? "Tap + to create your first job."
                                          : "Try a different filter or search term.")
                    )
                } else {
                    if !bookedJobs.isEmpty {
                        Section("Booked") {
                            ForEach(bookedJobs) { job in
                                Button {
                                    selectedJob = job
                                } label: {
                                    jobRow(job)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                deleteJobs(at: offsets, from: bookedJobs)
                            }
                        }
                    }

                    if !inProgressJobs.isEmpty {
                        Section("In Progress") {
                            ForEach(inProgressJobs) { job in
                                Button {
                                    selectedJob = job
                                } label: {
                                    jobRow(job)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                deleteJobs(at: offsets, from: inProgressJobs)
                            }
                        }
                    }

                    if !completedJobs.isEmpty {
                        Section("Completed") {
                            ForEach(completedJobs) { job in
                                Button {
                                    selectedJob = job
                                } label: {
                                    jobRow(job)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                deleteJobs(at: offsets, from: completedJobs)
                            }
                        }
                    }
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

        let statusText = normalizedJobStatusLabel(job.status)
        let location = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = job.startDate.formatted(date: .abbreviated, time: .omitted)
        let contractText = contractCount > 0 ? "\(contractCount) contract\(contractCount == 1 ? "" : "s")" : nil
        let subtitle = [statusText, location.isEmpty ? nil : location, contractText, date]
            .compactMap { $0 }
            .joined(separator: " • ")

        return HStack(alignment: .top, spacing: 12) {

            // Leading icon chip (matches Contracts/Invoices/Bookings)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Requests"))
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
        .padding(.vertical, 6)
    }

    /// Maps stored job.status values into a user-facing label for chips.
    private func normalizedJobStatusLabel(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if key == "completed" { return "COMPLETED" }
        if key == "canceled" || key == "cancelled" { return "CANCELED" }
        if key == "scheduled" { return "SCHEDULED" }

        return "ACTIVE"
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

    private func deleteJobs(at offsets: IndexSet, from source: [Job]) {
        let toDelete: [Job] = offsets.compactMap { idx -> Job? in
            guard idx < source.count else { return nil }
            return source[idx]
        }

        for job in toDelete {
            modelContext.delete(job)
        }

        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }
}
