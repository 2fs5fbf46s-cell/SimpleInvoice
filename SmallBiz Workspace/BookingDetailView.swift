import SwiftUI
import SwiftData

struct BookingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var booking: Booking

    @State private var showClientPicker = false

    private let statuses = ["scheduled", "completed", "canceled"]

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $booking.title)
                TextField("Location", text: $booking.locationName)
            }

            Section("Customer") {
                HStack {
                    Text("Client")
                    Spacer()
                    Text(booking.client?.name ?? "Select")
                        .foregroundStyle(.secondary)
                }

                Button("Select Client") { showClientPicker = true }

                if booking.client != nil {
                    Button(role: .destructive) {
                        booking.client = nil
                        try? modelContext.save()
                    } label: {
                        Text("Clear Client")
                    }
                }
            }

            Section("Schedule") {
                DatePicker("Start", selection: $booking.startDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $booking.endDate, displayedComponents: [.date, .hourAndMinute])
            }

            Section("Status") {
                Picker("Status", selection: $booking.status) {
                    ForEach(statuses, id: \.self) { s in
                        Text(s.capitalized).tag(s)
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $booking.notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(booking.title.isEmpty ? "Booking" : booking.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: booking) { _, _ in
            // lightweight autosave
            try? modelContext.save()
        }
        .sheet(isPresented: $showClientPicker) {
            NavigationStack {
                ClientPickerManualFetchView(selectedClient: Binding(
                    get: { booking.client },
                    set: { booking.client = $0; try? modelContext.save() }
                ))
                .navigationTitle("Select Client")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showClientPicker = false }
                    }
                }
            }
        }
    }
}
