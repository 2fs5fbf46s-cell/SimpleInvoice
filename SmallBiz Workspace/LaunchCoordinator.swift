import Foundation
import Combine
import OSLog
import SwiftData

@MainActor
final class LaunchCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case paintingInitialScreen
        case preparingStorage
        case runningMigrations
        case restoringBusiness
        case loadingWorkspace
        case ready
        case failed(String)

        var message: String {
            switch self {
            case .idle, .paintingInitialScreen:
                return "Preparing your workspace..."
            case .preparingStorage:
                return "Preparing storage..."
            case .runningMigrations:
                return "Checking workspace updates..."
            case .restoringBusiness:
                return "Restoring your business..."
            case .loadingWorkspace:
                return "Loading workspace..."
            case .ready:
                return "Opening workspace..."
            case .failed:
                return "We couldn't finish startup."
            }
        }

        var logName: String {
            switch self {
            case .idle:
                return "idle"
            case .paintingInitialScreen:
                return "paintingInitialScreen"
            case .preparingStorage:
                return "preparingStorage"
            case .runningMigrations:
                return "runningMigrations"
            case .restoringBusiness:
                return "restoringBusiness"
            case .loadingWorkspace:
                return "loadingWorkspace"
            case .ready:
                return "ready"
            case .failed:
                return "failed"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelContainer: ModelContainer?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SmallBizWorkspace",
        category: "Launch"
    )

    private let minimumDisplayTime: TimeInterval
    private var launchTask: Task<Void, Never>?
    private var launchStartedAt: Date?
    private var pendingIncomingURLs: [URL] = []

    init(minimumDisplayTime: TimeInterval = 0.45) {
        self.minimumDisplayTime = minimumDisplayTime
    }

    var isReady: Bool {
        phase == .ready && modelContainer != nil
    }

    func start(activeBusiness: ActiveBusinessStore) {
        guard launchTask == nil, !isReady else { return }
        if case .failed = phase { return }

        launchTask = Task { [weak self] in
            await self?.run(activeBusiness: activeBusiness)
        }
    }

    func retry(activeBusiness: ActiveBusinessStore) {
        launchTask?.cancel()
        launchTask = nil
        modelContainer = nil
        transition(to: .idle)
        start(activeBusiness: activeBusiness)
    }

    func queueIncomingURL(_ url: URL) {
        pendingIncomingURLs.append(url)
        log("Queued incoming URL until workspace is ready.")
    }

    func consumePendingIncomingURLs() -> [URL] {
        let urls = pendingIncomingURLs
        pendingIncomingURLs.removeAll()
        return urls
    }

    private func run(activeBusiness: ActiveBusinessStore) async {
        let startedAt = Date()
        launchStartedAt = startedAt

        defer {
            launchTask = nil
        }

        do {
            transition(to: .paintingInitialScreen)

            // Give SwiftUI one clean turn to commit the lightweight shell before
            // any SwiftData store work begins.
            try await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            transition(to: .preparingStorage)
            let container = try AppModelContainerFactory.makeContainer()
            modelContainer = container
            let context = container.mainContext

            transition(to: .runningMigrations)
            try warmContainer(modelContext: context)
            try BusinessMigration.runIfNeeded(
                modelContext: context,
                activeBiz: activeBusiness
            )

            transition(to: .restoringBusiness)
            try activeBusiness.loadOrCreateDefaultBusiness(modelContext: context)

            transition(to: .loadingWorkspace)
            await waitForMinimumDisplayTime(since: startedAt)
            guard !Task.isCancelled else { return }

            transition(to: .ready)
        } catch is CancellationError {
            log("Startup cancelled.")
        } catch {
            await waitForMinimumDisplayTime(since: startedAt)
            transition(to: .failed(Self.errorMessage(from: error)))
        }
    }

    private func warmContainer(modelContext: ModelContext) throws {
        var descriptor = FetchDescriptor<Business>()
        descriptor.fetchLimit = 1
        _ = try modelContext.fetch(descriptor)
    }

    private func waitForMinimumDisplayTime(since startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = minimumDisplayTime - elapsed
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    private func transition(to nextPhase: Phase) {
        let now = Date()
        let elapsed = launchStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let formattedElapsed = String(format: "%.3f", elapsed)

        if case .failed(let message) = nextPhase {
            log("Phase \(nextPhase.logName) at +\(formattedElapsed)s: \(message)")
        } else {
            log("Phase \(nextPhase.logName) at +\(formattedElapsed)s")
        }

        phase = nextPhase
    }

    private func log(_ message: String) {
        SBWLog.launch.note("[Launch] \(message)")
        Self.logger.info("\(message, privacy: .public)")
    }

    private static func errorMessage(from error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? String(describing: error) : description
    }
}

enum AppModelContainerFactory {
    /// The authoritative model list.
    ///
    /// Tests build their own in-memory containers from this rather than keeping
    /// parallel lists, which drift: a newly added `@Model` silently isn't covered
    /// by a test schema nobody remembered to update.
    ///
    /// If a test traps inside `save()`, the usual cause is not the schema — it is
    /// a `ModelContainer` that was not retained. `try makeInMemoryContainer().mainContext`
    /// releases the container at the end of the expression and leaves the context
    /// pointing at nothing. Hold the container for the life of the test.
    static let models: [any PersistentModel.Type] = [
            Business.self,
            BusinessProfile.self,
            PublishedBusinessSite.self,
            Client.self,
            Invoice.self,
            LineItem.self,
            CatalogItem.self,
            Contract.self,
            ContractSignature.self,
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
            InvoicePayment.self,
            ContractAttachment.self,

            Job.self,
            Blockout.self,
            AppNotification.self,

            Expense.self,
            ExpenseAttachment.self,

            RecurringInvoiceSchedule.self
    ]

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// An isolated in-memory container over the same models. For tests.
    ///
    /// `cloudKitDatabase` defaults to `.automatic`, which stands up a real
    /// `NSCloudKitMirroringDelegate` even for an in-memory store, visible in
    /// test logs as mirroring setup/teardown noise on every container. Tests
    /// never need CloudKit sync, so disable it here.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
