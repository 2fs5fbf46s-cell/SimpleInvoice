import OSLog
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
    @State private var readyServicesTask: Task<Void, Never>? = nil

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(lock)
                .environmentObject(activeBiz)

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
        guard newPhase == .active, let context = readyModelContext else { return }

        Task {
            await runWorkspaceServices(context: context)
        }
    }

    @MainActor
    private func startReadyServicesIfNeeded() {
        guard let context = readyModelContext else { return }

        PushSyncCoordinator.shared.register {
            await runPushSync(context: context)
        }

        readyServicesTask?.cancel()
        readyServicesTask = Task {
            processQueuedIncomingURLs(context: context)
            await runWorkspaceServices(context: context)
        }
    }

    /// What a push wake refreshes — only the pulls a backend event can
    /// change, kept small to fit the ~30s iOS allows a background wake.
    @MainActor
    private func runPushSync(context: ModelContext) async {
        let businessID = activeBiz.activeBusinessID
        if let businessID {
            await BusinessRegistrationService.ensureRegistered(businessID: businessID)
        }
        await EstimateAcceptancePullService.pullAndMaterialize(context: context, businessID: businessID)
        await InvoiceActivityPullService.pull(context: context, businessID: businessID)
        await ContractActivityPullService.pull(context: context, businessID: businessID)
        await RecurringInvoicePullService.pullAndMaterialize(context: context, businessID: businessID)
        await DepositStatusSyncService.refreshPendingDeposits(context: context, businessID: businessID)
        await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: businessID)
    }

    @MainActor
    private func runWorkspaceServices(context: ModelContext) async {
        if activeBiz.activeBusinessID == nil, Self.hasBusinesses(context: context) {
            do {
                try activeBiz.loadOrCreateDefaultBusiness(modelContext: context)
            } catch {
                SBWLog.launch.problem("[Launch] Active business restore after ready failed: \(error)")
            }
        }

        // Claim this business (or reuse its stored token) before any portal call.
        if let businessID = activeBiz.activeBusinessID {
            await BusinessRegistrationService.ensureRegistered(businessID: businessID)
        }

        EstimateDecisionSync.applyPendingDecisions(in: context)
        BusinessSitePublishService.shared.startMonitoring(context: context)
        await BusinessSitePublishService.shared.syncQueuedSites(context: context)
        await LocalReminderScheduler.shared.refreshReminders(modelContext: context, activeBusinessID: activeBiz.activeBusinessID)
        await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: activeBiz.activeBusinessID)
        // Generation itself is server/push-driven; this is the "next launch as
        // a fallback" leg, covering a push that never arrived or was denied.
        await RecurringInvoicePullService.pullAndMaterialize(context: context, businessID: activeBiz.activeBusinessID)
        // Same reasoning: estimate decisions (accepted and declined) are
        // server/push-driven (POST /api/portal/estimate/decision), this is
        // the fallback leg — and the only one, now that per-estimate status
        // polling is gone.
        await EstimateAcceptancePullService.pullAndMaterialize(context: context, businessID: activeBiz.activeBusinessID)
        await InvoiceActivityPullService.pull(context: context, businessID: activeBiz.activeBusinessID)
        await ContractActivityPullService.pull(context: context, businessID: activeBiz.activeBusinessID)
        // Deposits are a soft reminder, not a gate, so a plain periodic
        // poll of each pending deposit's own payment status is enough —
        // no push/pull pair needed here.
        await DepositStatusSyncService.refreshPendingDeposits(context: context, businessID: activeBiz.activeBusinessID)
    }

    @MainActor
    private func refreshBusinessScopedServices(for businessID: UUID?) {
        // Point the backend client at this business before anything talks to it.
        // Every business-scoped call is authorized by this token, so it has to be
        // in place before the services below run.
        BusinessRegistrationService.activate(businessID: businessID)

        guard let context = readyModelContext else { return }

        Task {
            if let businessID {
                await BusinessRegistrationService.ensureRegistered(businessID: businessID)
            }

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

        SBWLog.launch.note("[Launch] Processing \(queuedURLs.count) queued incoming URL(s).")
        for url in queuedURLs {
            EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: context)
        }
    }

    @MainActor
    private static func hasBusinesses(context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Business>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).isEmpty) == false
    }
}
