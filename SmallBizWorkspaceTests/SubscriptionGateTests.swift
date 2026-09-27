import XCTest
import SwiftUI
import StoreKitTest
@testable import SmallBizWorkspace

/// `SubscriptionStore`/`SubscriptionGate` against a real StoreKit Testing
/// session (Subscription.storekit).
///
/// Only the no-purchase path is covered here. `SKTestSession.buyProduct`/
/// `expireSubscription` — which need the StoreKit test daemon to persist
/// state — reliably fail in this sandboxed, headless `xcodebuild test`
/// environment with `SKInternalErrorDomain Code=3` ("Error saving
/// configuration file") regardless of the .storekit file's content, schema
/// version, or a freshly-erased simulator; the same session's read-only
/// `.load()` path (this test) works fine, so the daemon itself isn't wired
/// up for local persistence here. Verify the purchase/expiry paths from
/// Xcode's own GUI test runner instead, where SKTestSession is well-proven
/// to work — and the manual simulator walkthrough (paywall → purchase →
/// gate opens) covers the same ground end to end regardless.
@MainActor
final class SubscriptionGateTests: XCTestCase {

    private var session: SKTestSession!
    private var store: SubscriptionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = Bundle(for: Self.self).url(forResource: "Subscription", withExtension: "storekit")!
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        store = SubscriptionStore()
    }

    override func tearDownWithError() throws {
        session = nil
        store = nil
        try super.tearDownWithError()
    }

    func testNoEntitlementBlocksTheGate() async throws {
        await store.load()
        XCTAssertFalse(store.isEntitled)
        XCTAssertEqual(store.state, .notEntitled)

        var paywallShown = false
        let binding = Binding(get: { paywallShown }, set: { paywallShown = $0 })
        let allowed = SubscriptionGate.allow(store, present: binding)

        XCTAssertFalse(allowed)
        XCTAssertTrue(paywallShown)
    }
}
