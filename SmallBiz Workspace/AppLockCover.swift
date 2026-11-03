import SwiftUI

/// Covers the app while it's locked, and in the app switcher while the lock
/// is on. A cover rather than a swap, so whatever was open is still there
/// after unlocking.
struct AppLockCover: View {
    @EnvironmentObject private var lock: AppLockManager
    @Environment(\.scenePhase) private var scenePhase

    /// Asks once each time the app comes forward; after a cancel the button
    /// is there. Face ID's own prompt makes the app inactive and active
    /// again, which would otherwise ask in a loop.
    @State private var askedThisTime = false

    var body: some View {
        if lock.isEnabled && (!lock.isUnlocked || lock.isObscured) {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.scaledSystem(size: 40, relativeTo: .largeTitle))
                        .foregroundStyle(SBWTheme.brand)
                    Text("SmallBiz Workspace is locked")
                        .font(.title3.weight(.semibold))
                    if !lock.isUnlocked {
                        Button("Unlock") {
                            Task { await lock.unlock() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SBWTheme.brand)
                    }
                }
                .padding()
            }
            .task(id: scenePhase) { await askIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { askedThisTime = false }
            }
        }
    }

    private func askIfNeeded() async {
        guard scenePhase == .active, !lock.isUnlocked, !askedThisTime else { return }
        askedThisTime = true
        await lock.unlock()
    }
}
