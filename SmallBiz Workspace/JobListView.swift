//
//  JobsListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct JobsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]

    @State private var searchText: String = ""
    @State private var filter: JobFilter = .active

    private enum JobFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case canceled = "Canceled"

        var id: String { rawValue }
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

        return jobs.filter { matchesFilter($0) && matchesSearch($0) }
    }

    var body: some View {
        List {
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
                    jobs.isEmpty ? "No Jobs Yet" : "No Results",
                    systemImage: "briefcase",
                    description: Text(jobs.isEmpty
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
        .navigationTitle("Jobs")
        .searchable(text: $searchText, prompt: "Search jobs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createJob() } label: { Image(systemName: "plus") }
            }
        }
    }

    private func jobRow(_ job: Job) -> some View {
        let contractCount = job.contracts?.count ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title.isEmpty ? "Job" : job.title)
                    .font(.headline)

                Spacer()

                if contractCount > 0 {
                    Text("\(contractCount) Contract\(contractCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(job.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(job.startDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func createJob() {
        // NOTE: You can later set businessID to the active business.
        // For now we keep it functional and offline-first.
        let job = Job(
            businessID: UUID(),
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )
        job.title = ""
        job.status = "scheduled"

        modelContext.insert(job)
        try? modelContext.save()
    }

    private func deleteJobs(at offsets: IndexSet) {
        let toDelete: [Job] = offsets.compactMap { idx -> Job? in
            guard idx < filteredJobs.count else { return nil }
            return filteredJobs[idx]
        }

        for job in toDelete {
            modelContext.delete(job)
        }

        try? modelContext.save()
    }
}
