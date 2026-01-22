import SwiftUI
import SwiftData

struct NewBookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var locationName = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var notes = ""

    @State private var showClientPicker = false
    @State private var selectedClient: Client? = nil

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                TextField("Location", text: $locationName)
            }

            Section("Customer") {
                HStack {
                    Text("Client")
                    Spacer()
                    Text(selectedClient?.name ?? "Select")
                        .foregroundStyle(.secondary)
                }
                Button("Select Client") { showClientPicker = true }
            }

            Section("Schedule") {
                DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle("New Booking")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showClientPicker) {
            NavigationStack {
                ClientPickerManualFetchView(selectedClient: $selectedClient)
                    .navigationTitle("Select Client")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showClientPicker = false }
                        }
                    }
            }
        }
    }

    private func save() {
        let b = Booking(
            title: title,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            status: "scheduled",
            locationName: locationName,
            client: selectedClient
        )
        modelContext.insert(b)
        try? modelContext.save()
        dismiss()
    }
}
