import SwiftUI
import SwiftData
import UIKit

@main
struct SmallBizWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var launch = LaunchCoordinator()
    @StateObject private var lock = AppLockManager()
    @StateObject private var activeBiz = ActiveBusinessStore()
    @State private var estimateSyncPollTask: Task<Void, Never>? = nil
    @State private var readyServicesTask: Task<Void, Never>? = nil

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(lock)
                .environmentObject(activeBiz)
                .preferredColorScheme(.dark)

                // Close Safari when portal redirects back to app via scheme.
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    handleIncomingURL(url)
                }

                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
                .onChange(of: activeBiz.activeBusinessID) { _, newBusinessID in
                    refreshBusinessScopedServices(for: newBusinessID)
                }
                .task {
                    launch.start(activeBusiness: activeBiz)
                }
                .onChange(of: launch.phase) { _, _ in
                    startReadyServicesIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if launch.isReady, let container = launch.modelContainer {
            RootView()
                .modelContainer(container)
        } else {
            AppStartupShellView(
                phase: launch.phase,
                retry: {
                    launch.retry(activeBusiness: activeBiz)
                }
            )
        }
    }

    @MainActor
    private var readyModelContext: ModelContext? {
        guard launch.isReady else { return nil }
        return launch.modelContainer?.mainContext
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) {
        PortalReturnRouter.shared.handle(url)
        NotificationRouter.shared.handleIncomingURL(url)

        guard let context = readyModelContext else {
            launch.queueIncomingURL(url)
            return
        }

        EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: context)
    }

    @MainActor
    private func handleScenePhase(_ newPhase: ScenePhase) {
        guard newPhase == .active else {
            estimateSyncPollTask?.cancel()
            estimateSyncPollTask = nil
            return
        }

        guard let context = readyModelContext else { return }

        Task {
            await runWorkspaceServices(context: context)
            startEstimatePolling(context: context)
        }
    }

    @MainActor
    private func startReadyServicesIfNeeded() {
        guard let context = readyModelContext else { return }

        readyServicesTask?.cancel()
        readyServicesTask = Task {
            processQueuedIncomingURLs(context: context)
            await runWorkspaceServices(context: context)

            if scenePhase == .active {
                startEstimatePolling(context: context)
            }
        }
    }

    @MainActor
    private func runWorkspaceServices(context: ModelContext) async {
        if activeBiz.activeBusinessID == nil, Self.hasBusinesses(context: context) {
            do {
                try activeBiz.loadOrCreateDefaultBusiness(modelContext: context)
            } catch {
                print("[Launch] Active business restore after ready failed: \(error)")
            }
        }

        await EstimatePortalSyncService.sync(context: context)
        BusinessSitePublishService.shared.startMonitoring(context: context)
        await BusinessSitePublishService.shared.syncQueuedSites(context: context)
        await LocalReminderScheduler.shared.refreshReminders(modelContext: context, activeBusinessID: activeBiz.activeBusinessID)
        await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: activeBiz.activeBusinessID)
    }

    @MainActor
    private func refreshBusinessScopedServices(for businessID: UUID?) {
        guard let context = readyModelContext else { return }

        Task {
            await LocalReminderScheduler.shared.refreshReminders(
                modelContext: context,
                activeBusinessID: businessID
            )
            await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: businessID)
        }
    }

    @MainActor
    private func processQueuedIncomingURLs(context: ModelContext) {
        let queuedURLs = launch.consumePendingIncomingURLs()
        guard !queuedURLs.isEmpty else { return }

        print("[Launch] Processing \(queuedURLs.count) queued incoming URL(s).")
        for url in queuedURLs {
            EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: context)
        }
    }

    @MainActor
    private func startEstimatePolling(context: ModelContext) {
        estimateSyncPollTask?.cancel()
        estimateSyncPollTask = Task {
            while !Task.isCancelled {
                await EstimatePortalSyncService.sync(context: context)
                try? await Task.sleep(nanoseconds: 90_000_000_000)
            }
        }
    }

    @MainActor
    private static func hasBusinesses(context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Business>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).isEmpty) == false
    }
}
