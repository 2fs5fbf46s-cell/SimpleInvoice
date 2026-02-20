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
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 14) {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Details")
                                .font(.headline)
                            fieldRow(title: "Title") {
                                TextField("Title", text: $title)
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider().opacity(0.22)
                            fieldRow(title: "Location") {
                                TextField("Location", text: $locationName)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Customer")
                                .font(.headline)
                            fieldRow(title: "Client") {
                                Text(selectedClient?.name ?? "Select")
                                    .foregroundStyle(.secondary)
                            }
                            Button("Select Client") { showClientPicker = true }
                                .buttonStyle(.bordered)
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Schedule")
                                .font(.headline)
                            DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                            DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes")
                                .font(.headline)
                            TextEditor(text: $notes)
                                .frame(minHeight: 90)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle("New Booking")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            content()
                .font(.subheadline)
        }
        .frame(minHeight: 42)
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
