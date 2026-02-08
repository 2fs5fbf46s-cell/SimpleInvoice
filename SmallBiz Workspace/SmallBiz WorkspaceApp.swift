import SwiftUI
import SwiftData

@main
struct SmallBizWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase

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
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else { return }
                PortalReturnRouter.shared.handle(url)
                EstimateDecisionSync.handlePortalEstimateDecisionURL(url, context: Self.container.mainContext)
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
                startEstimatePolling(context: context)
            }
            .task {
                let context = Self.container.mainContext
                await EstimatePortalSyncService.sync(context: context)
                BusinessSitePublishService.shared.startMonitoring(context: context)
                await BusinessSitePublishService.shared.syncQueuedSites(context: context)
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
            Blockout.self
        ])

        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("❌ Failed to create ModelContainer: \(error)")
        }
    }()
}
