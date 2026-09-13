import Foundation

/// How often to ask the portal whether an estimate has been decided.
///
/// The poll used to run every 90 seconds for as long as the app was foregrounded,
/// regardless of whether the business had a single outstanding estimate — a device
/// with nothing to watch still woke the radio 40 times an hour. And a failing
/// network was polled at exactly the same rate as a healthy one, so an offline
/// user generated the same traffic as an online one.
///
/// Pure and separately testable, because the cost of getting it wrong is a battery
/// complaint nobody can reproduce.
enum EstimatePollSchedule {

    /// Normal cadence while something is genuinely awaiting a decision.
    static let activeInterval: TimeInterval = 90

    /// Nothing outstanding. Still checks occasionally, because an estimate can be
    /// sent from another device.
    static let idleInterval: TimeInterval = 15 * 60

    /// Ceiling for backoff, so a long outage settles rather than escalating.
    static let maxInterval: TimeInterval = 15 * 60

    /// Seconds to wait before the next poll.
    ///
    /// - Parameters:
    ///   - candidates: estimates currently awaiting a decision.
    ///   - consecutiveFailures: network failures since the last success.
    static func nextInterval(candidates: Int, consecutiveFailures: Int) -> TimeInterval {
        guard candidates > 0 else { return idleInterval }
        guard consecutiveFailures > 0 else { return activeInterval }

        // Double per failure: 90s, 3m, 6m, 12m, then hold at the ceiling. Capped
        // exponent so the shift cannot overflow on a very long outage.
        let exponent = min(consecutiveFailures, 8)
        let backoff = activeInterval * pow(2, Double(exponent))
        return min(backoff, maxInterval)
    }
}

/// What one sync pass found, so the caller can decide when to run again.
struct EstimateSyncOutcome: Equatable {
    /// Estimates that were awaiting a decision when the pass began.
    let candidates: Int
    let updated: Int
    let failed: Int

    static let none = EstimateSyncOutcome(candidates: 0, updated: 0, failed: 0)

    /// True when the network failed for everything tried — the signal to back off.
    /// A partial failure is not treated as an outage.
    var looksOffline: Bool {
        candidates > 0 && failed == candidates
    }
}
