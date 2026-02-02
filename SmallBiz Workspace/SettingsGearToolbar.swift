import SwiftUI

struct SettingsGearToolbarModifier<SettingsView: View>: ViewModifier {
    @State private var showSettings = false
    let settingsView: () -> SettingsView

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    settingsView()
                }
            }
    }
}

extension View {
    func settingsGear<SettingsView: View>(
        @ViewBuilder _ settingsView: @escaping () -> SettingsView
    ) -> some View {
        modifier(SettingsGearToolbarModifier(settingsView: settingsView))
    }
}
