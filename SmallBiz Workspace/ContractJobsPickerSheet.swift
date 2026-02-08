import SwiftUI

struct ContractJobsPickerSheet: View {
    let jobs: [Job]
    @Binding var selectedJobIDs: [UUID]
    @Binding var primaryJobID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [Job] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return jobs }
        return jobs.filter {
            $0.title.lowercased().contains(q) || $0.status.lowercased().contains(q)
        }
    }

    private var selectedSet: Set<UUID> {
        Set(selectedJobIDs)
    }

    var body: some View {
        List {
            if selectedJobIDs.isEmpty {
                Text("No linked jobs")
                    .foregroundStyle(.secondary)
            } else {
                Section("Linked Jobs") {
                    ForEach(jobs.filter { selectedSet.contains($0.id) }) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                Text(job.status.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if primaryJobID == job.id {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            primaryJobID = job.id
                        }
                    }

                    Button(role: .destructive) {
                        selectedJobIDs = []
                        primaryJobID = nil
                    } label: {
                        Text("Clear All")
                    }
                }
            }

            Section("All Jobs") {
                if filtered.isEmpty {
                    Text("No jobs found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { job in
                        Button {
                            toggle(job.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                    Text(job.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedSet.contains(job.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func toggle(_ id: UUID) {
        var set = Set(selectedJobIDs)
        if set.contains(id) {
            set.remove(id)
            if primaryJobID == id {
                primaryJobID = set.first
            }
        } else {
            set.insert(id)
            if primaryJobID == nil {
                primaryJobID = id
            }
        }
        selectedJobIDs = Array(set)
    }
}
