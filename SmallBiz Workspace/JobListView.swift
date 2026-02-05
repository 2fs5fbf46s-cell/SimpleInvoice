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
    @State private var filter: JobFilter = .active

    // ✅ New Job sheet (Clients-style)
    @State private var showingNewJob = false
    @State private var newJobDraft: Job? = nil

    private enum JobFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
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
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matchesSearch(_ job: Job) -> Bool {
            guard !q.isEmpty else { return true }
            return job.title.lowercased().contains(q)
            || job.notes.lowercased().contains(q)
            || job.locationName.lowercased().contains(q)
            || job.status.lowercased().contains(q)
        }

        func matchesFilter(_ job: Job) -> Bool {
            let status = job.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch filter {
            case .all:
                return true
            case .active:
                return !(status == "completed" || status == "canceled" || status == "cancelled")
            case .completed:
                return status == "completed"
            case .canceled:
                return status == "canceled" || status == "cancelled"
            }
        }

        return scopedJobs.filter { matchesFilter($0) && matchesSearch($0) }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                // Filter toggle (match other list screens)
                Section {
                    Picker("", selection: $filter) {
                        ForEach(JobFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if filteredJobs.isEmpty {
                    ContentUnavailableView(
                        scopedJobs.isEmpty ? "No Jobs Yet" : "No Results",
                        systemImage: "briefcase",
                        description: Text(scopedJobs.isEmpty
                                          ? "Tap + to create your first job."
                                          : "Try a different filter or search term.")
                    )
                } else {
                    ForEach(filteredJobs) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                        } label: {
                            jobRow(job)
                        }
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
        .settingsGear { BusinessProfileView() }
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
        let chip = SBWTheme.chip(forStatus: statusText)

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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.title.isEmpty ? "Job" : job.title)
                        .font(.headline)

                    Spacer()

                    if contractCount > 0 {
                        Text("\(contractCount) Contract\(contractCount == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(SBWTheme.cardStroke, lineWidth: 1))
                            .foregroundStyle(.secondary)
                    }
                }

                if !job.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(job.locationName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chip.fg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(chip.bg)
                        .clipShape(Capsule())

                    Spacer()

                    Text(job.startDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
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
}
