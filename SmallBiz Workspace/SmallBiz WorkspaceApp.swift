import SwiftUI
import SwiftData
import UIKit

@main
struct SmallBizWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var lock = AppLockManager()
    @StateObject private var activeBiz = ActiveBusinessStore()
    @State private var estimateSyncPollTask: Task<Void, Never>? = nil

    var body: some Scene {
        WindowGroup {
            AppLaunchGateView {
                RootView()
            }
            .environmentObject(lock)
            .environmentObject(activeBiz)
            .preferredColorScheme(.dark)

            // ✅ Close Safari when portal redirects back to app via scheme
            .onOpenURL { url in
                PortalReturnRouter.shared.handle(url)
                EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: Self.container.mainContext)
                NotificationRouter.shared.handleIncomingURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else { return }
                PortalReturnRouter.shared.handle(url)
                EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: Self.container.mainContext)
                NotificationRouter.shared.handleIncomingURL(url)
            }

            // ✅ Xcode 26.2: onChange closure expects ONE argument
            .onChange(of: scenePhase) { _, newPhase in
                let context = Self.container.mainContext
                guard newPhase == .active else {
                    estimateSyncPollTask?.cancel()
                    estimateSyncPollTask = nil
                    return
                }

                if activeBiz.activeBusinessID == nil {
                    do {
                        try activeBiz.loadOrCreateDefaultBusiness(modelContext: context)
                    } catch {
                        print("⚠️ Re-restore active business failed:", error)
                    }
                }

                Task { await EstimatePortalSyncService.sync(context: context) }
                BusinessSitePublishService.shared.startMonitoring(context: context)
                Task { await BusinessSitePublishService.shared.syncQueuedSites(context: context) }
                Task { await LocalReminderScheduler.shared.refreshReminders(modelContext: context, activeBusinessID: activeBiz.activeBusinessID) }
                Task { await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: activeBiz.activeBusinessID) }
                startEstimatePolling(context: context)
            }
            .onChange(of: activeBiz.activeBusinessID) { _, newBusinessID in
                let context = Self.container.mainContext
                Task {
                    await LocalReminderScheduler.shared.refreshReminders(
                        modelContext: context,
                        activeBusinessID: newBusinessID
                    )
                    await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: newBusinessID)
                }
            }
            .task {
                let context = Self.container.mainContext
                await EstimatePortalSyncService.sync(context: context)
                BusinessSitePublishService.shared.startMonitoring(context: context)
                await BusinessSitePublishService.shared.syncQueuedSites(context: context)
                await LocalReminderScheduler.shared.refreshReminders(modelContext: context, activeBusinessID: activeBiz.activeBusinessID)
                await NotificationInboxService.shared.refreshIfNeeded(modelContext: context, businessId: activeBiz.activeBusinessID)
                if scenePhase == .active {
                    startEstimatePolling(context: context)
                }
            }
        }
        .modelContainer(Self.container)
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

    // MARK: - SwiftData Container (CloudKit with safe fallbacks)
    private static var container: ModelContainer = {
        let schema = Schema([
            Business.self,
            BusinessProfile.self,
            PublishedBusinessSite.self,
            Client.self,
            Invoice.self,
            LineItem.self,
            CatalogItem.self,
            Contract.self,
            ClientAttachment.self,
            JobAttachment.self,

            AuditEvent.self,

            PortalIdentity.self,
            PortalSession.self,
            PortalInvite.self,
            PortalAuditEvent.self,
            EstimateDecisionRecord.self,

            ContractTemplate.self,

            Folder.self,
            FileItem.self,

            InvoiceAttachment.self,
            ContractAttachment.self,

            Job.self,
            Blockout.self,
            AppNotification.self
        ])

        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("❌ Failed to create ModelContainer: \(error)")
        }
    }()
}
