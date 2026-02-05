import SwiftUI
import SwiftData

struct BookingPortalCustomizeView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Booking Portal") {
                Toggle("Enable Booking Portal", isOn: Bindable(profile).bookingEnabled)

                Text("These details are saved locally and will appear on your booking page in a future update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Business Hours") {
                TextEditor(text: Bindable(profile).bookingHoursText)
                    .frame(minHeight: 140)
                    .font(.body)

                Text("Example: Mon: 9am-5pm\nTue: 9am-5pm")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Booking Instructions") {
                TextEditor(text: Bindable(profile).bookingInstructions)
                    .frame(minHeight: 120)
                    .font(.body)
            }
        }
        .navigationTitle("Customize Info")
        .onChange(of: profile.bookingEnabled) { _, _ in try? modelContext.save() }
        .onChange(of: profile.bookingHoursText) { _, _ in try? modelContext.save() }
        .onChange(of: profile.bookingInstructions) { _, _ in try? modelContext.save() }
    }
}

#Preview {
    BookingPortalCustomizeView(profile: BusinessProfile())
}
