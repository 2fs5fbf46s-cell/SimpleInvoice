import SwiftUI
import SwiftData

@main
struct SmallBizWorkspaceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var lock = AppLockManager()
    @StateObject private var activeBiz = ActiveBusinessStore()

    var body: some Scene {
        WindowGroup {
            AppLaunchGateView {
                RootView()
            }
            .environmentObject(lock)
            .environmentObject(activeBiz)

            // ✅ Close Safari when portal redirects back to app via scheme
            .onOpenURL { url in
                PortalReturnRouter.shared.handle(url)
            }

            // ✅ Xcode 26.2: onChange closure expects ONE argument
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let context = Self.container.mainContext

                if activeBiz.activeBusinessID == nil {
                    do {
                        try activeBiz.loadOrCreateDefaultBusiness(modelContext: context)
                    } catch {
                        print("⚠️ Re-restore active business failed:", error)
                    }
                }
            }
        }
        .modelContainer(Self.container)
    }

    // MARK: - SwiftData Container (CloudKit with safe fallbacks)
    private static var container: ModelContainer = {
        let schema = Schema([
            Business.self,
            BusinessProfile.self,
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
