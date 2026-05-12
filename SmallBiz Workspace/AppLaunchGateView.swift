//
//  AppLaunchGateView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Compatibility launch gate. Prefer using LaunchCoordinator at the app root so
/// the first SwiftUI frame can render before any SwiftData container work begins.
struct AppLaunchGateView<Content: View>: View {
    @EnvironmentObject private var activeBusiness: ActiveBusinessStore

    private let content: () -> Content

    @StateObject private var launch: LaunchCoordinator

    init(minimumDisplayTime: TimeInterval = 0.45,
         @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        _launch = StateObject(wrappedValue: LaunchCoordinator(minimumDisplayTime: minimumDisplayTime))
    }

    var body: some View {
        Group {
            if launch.isReady, let container = launch.modelContainer {
                content()
                    .modelContainer(container)
            } else {
                AppStartupShellView(
                    phase: launch.phase,
                    retry: {
                        launch.retry(activeBusiness: activeBusiness)
                    }
                )
            }
        }
        .task {
            launch.start(activeBusiness: activeBusiness)
        }
    }
}
