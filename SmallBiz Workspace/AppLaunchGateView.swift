//
//  AppLaunchGateView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Branded launch gate that:
/// - warms the SwiftData/Cloud store (reduces cold-start weirdness)
/// - runs BusinessMigration if needed
/// - restores/creates the active business
/// - enforces a minimum display time to prevent “blink”
///
/// Usage:
/// AppLaunchGateView { RootView() }
struct AppLaunchGateView<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBusiness: ActiveBusinessStore

    private let minimumDisplayTime: TimeInterval
    private let content: () -> Content

    @State private var isReady = false
    @State private var didStart = false
    @State private var errorText: String? = nil

    init(minimumDisplayTime: TimeInterval = 0.45,
         @ViewBuilder content: @escaping () -> Content) {
        self.minimumDisplayTime = minimumDisplayTime
        self.content = content
    }

    var body: some View {
        ZStack {
            if isReady {
                content()
            } else {
                // ✅ Your project’s branded loading view file is BrandingLoadView.swift
                BrandingLoadView(
                    title: "SmallBiz Workspace",
                    subtitle: errorText ?? "Loading workspace…"
                )                                          
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await prepare()
        }
    }

    @MainActor
    private func prepare() async {
        let start = Date()

        do {
            
            
            // 1) Warm the container/store (forces SwiftData store init early)
            try warmContainer()

            // 2) Migrations (your function requires activeBiz:)
            try BusinessMigration.runIfNeeded(
                modelContext: modelContext,
                activeBiz: activeBusiness
            )

            // 3) Restore or create active business (your store owns this)
            try activeBusiness.loadOrCreateDefaultBusiness(modelContext: modelContext)

            // 4) Minimum display time to prevent flicker
            let elapsed = Date().timeIntervalSince(start)
            let remaining = minimumDisplayTime - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            withAnimation(.easeOut(duration: 0.15)) {
                isReady = true
            }
        } catch {
            // Still respect minimum time to avoid harsh flash on failure
            let elapsed = Date().timeIntervalSince(start)
            let remaining = minimumDisplayTime - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            // Non-blocking: allow app to open, but show an FYI.
            errorText = "Startup note: \(String(describing: error))"
            isReady = true

            print("⚠️ AppLaunchGateView prepare() error:", error)
        }
    }

    private func warmContainer() throws {
        // ✅ Your BusinessMigration uses Business, so we warm that type.
        var descriptor = FetchDescriptor<Business>()
        descriptor.fetchLimit = 1
        _ = try modelContext.fetch(descriptor)
    }
}
