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
            // ✅ Optional upgrade: when returning from background, re-ensure a valid active business
            // (prevents edge cases where activeBusinessID is nil after cold/restore/CloudKit hiccups)
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let context = Self.container.mainContext

                // Only re-run restore if needed (keeps it lightweight)
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

            // ✅ audit
            AuditEvent.self,

            // ✅ Portal groundwork
            PortalIdentity.self,
            PortalSession.self,
            PortalInvite.self,
            PortalAuditEvent.self,

            // ✅ Templates must be in schema or they won't persist
            ContractTemplate.self,

            // ✅ Files
            Folder.self,
            FileItem.self,

            // ✅ Join models (use your actual names)
            InvoiceAttachment.self,
            ContractAttachment.self,

            Job.self,
            Blockout.self
        ])

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("SmallBizWorkspace", isDirectory: true)

        do {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            print("⚠️ Could not create Application Support directory:", error)
        }

        let cloudURL = baseDir.appendingPathComponent("SwiftData-Cloud.store")
        let localURL = baseDir.appendingPathComponent("SwiftData-Local.store")

        // 1) Try CloudKit store
        do {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                url: cloudURL,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ SwiftData CloudKit container loaded:", cloudURL)
            return container
        } catch {
            print("⚠️ CloudKit ModelContainer failed:", error)
        }

        // 2) Try local store
        do {
            let localConfig = ModelConfiguration(
                schema: schema,
                url: localURL
            )
            let container = try ModelContainer(for: schema, configurations: [localConfig])
            print("✅ SwiftData local container loaded:", localURL)
            return container
        } catch {
            print("❌ Local ModelContainer also failed:", error)
        }

        // 3) Last resort: in-memory so the app can open (and you can see UI)
        do {
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [memoryConfig])
            print("✅ SwiftData in-memory container loaded as last resort.")
            return container
        } catch {
            fatalError("❌ Even in-memory ModelContainer failed: \(error)")
        }
    }()
}
