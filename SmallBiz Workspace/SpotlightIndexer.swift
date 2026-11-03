import Combine
import CoreSpotlight
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Puts the active business's clients, invoices, estimates, jobs and
/// contracts into iPhone Spotlight, so "SI-2026-014" or a client's name typed
/// on the Home Screen opens the record.
///
/// Rebuilt whole each time (the app going to the background, a business
/// switch, the lock being turned on or off): one business's records at a
/// time, so a result always belongs to the business that's open, and nothing
/// deleted lingers. Empty while "Require Face ID" is on. Owners who don't
/// want them in Spotlight otherwise turn it off in Settings › Apps ›
/// SmallBiz Workspace › Search, which iOS honors without us.
@MainActor
enum SpotlightIndexer {
    private static let log = Logger(subsystem: "SmallBizWorkspace", category: "spotlight")

    static func reindex(context: ModelContext, businessID: UUID?) async {
        let index = CSSearchableIndex.default()
        do {
            try await index.deleteAllSearchableItems()
            // With the app locked, names and amounts mustn't be one Home
            // Screen search away.
            guard let businessID, !AppLockManager.isEnabledInDefaults else { return }
            let items = SearchDocuments.all(businessID: businessID, context: context, includeExpenses: false)
                .map(item)
            guard !items.isEmpty else { return }
            try await index.indexSearchableItems(items)
        } catch {
            log.error("Spotlight reindex failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func item(_ document: SearchDocument) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = document.title
        attributes.contentDescription = document.subtitle
        attributes.textContent = document.haystack
        // Spotlight matches keywords far more readily than body text: without
        // these, an invoice's line items ("Wedding DJ") didn't find it.
        var seen = Set<String>()
        attributes.keywords = document.haystack
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count > 1 && seen.insert($0).inserted }
            .prefix(64)
            .map { $0 }
        return CSSearchableItem(
            uniqueIdentifier: document.id,
            domainIdentifier: document.kind.rawValue,
            attributeSet: attributes
        )
    }
}

/// Holds a Spotlight tap until `AppTabView` is there to open it. A tap can
/// launch the app, and the tabs only exist once the database is ready.
@MainActor
final class SpotlightRouter: ObservableObject {
    static let shared = SpotlightRouter()

    @Published private(set) var pendingIdentifier: String?

    func open(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        pendingIdentifier = identifier
    }

    func consume() {
        pendingIdentifier = nil
    }
}
