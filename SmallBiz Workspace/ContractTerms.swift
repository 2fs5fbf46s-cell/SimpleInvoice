//
//  ContractTerms.swift
//  SmallBiz Workspace
//

import Foundation

/// The cancellation tiers, final-balance deadline and governing state a
/// contract is written with.
///
/// Defaults come from the business (`BusinessProfile.contractCancel*`,
/// Business → Contract Terms) and can be changed for one contract on the
/// New Contract screen. They're only used to write the contract's text,
/// so nothing per-contract is stored: the numbers live in the body.
struct ContractTerms: Equatable {
    /// Cancelling more than this many days out: the deposit is kept.
    var cancelEarlyDays: Int = 30
    /// From `cancelEarlyDays` down to `cancelLateDays` + 1 days: this
    /// percent of the total.
    var cancelMidPercent: Int = 75
    /// This many days or fewer: `cancelLatePercent` of the total.
    var cancelLateDays: Int = 7
    var cancelLatePercent: Int = 100
    /// The final balance is due this many hours before the event starts.
    var balanceDueHours: Int = 48
    /// e.g. "South Carolina". Blank: the state the Provider operates in.
    var governingState: String = ""

    static let balanceDueHourOptions = [24, 48, 72]

    init() {}

    init(profile: BusinessProfile?) {
        guard let profile else { return }
        cancelEarlyDays = profile.contractCancelEarlyDays
        cancelMidPercent = profile.contractCancelMidPercent
        cancelLateDays = profile.contractCancelLateDays
        cancelLatePercent = profile.contractCancelLatePercent
        balanceDueHours = profile.contractBalanceDueHours
        governingState = profile.contractGoverningState
    }

    /// Always a readable set of tiers: days that don't overlap, percents
    /// 0–100, and a late fee at least as high as the middle one.
    var normalized: ContractTerms {
        var t = self
        t.cancelEarlyDays = min(max(t.cancelEarlyDays, 2), 365)
        t.cancelLateDays = min(max(t.cancelLateDays, 1), t.cancelEarlyDays - 1)
        t.cancelMidPercent = min(max(t.cancelMidPercent, 0), 100)
        t.cancelLatePercent = min(max(t.cancelLatePercent, t.cancelMidPercent), 100)
        t.balanceDueHours = min(max(t.balanceDueHours, 0), 24 * 30)
        t.governingState = t.governingState.trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }

    func save(to profile: BusinessProfile) {
        let t = normalized
        profile.contractCancelEarlyDays = t.cancelEarlyDays
        profile.contractCancelMidPercent = t.cancelMidPercent
        profile.contractCancelLateDays = t.cancelLateDays
        profile.contractCancelLatePercent = t.cancelLatePercent
        profile.contractBalanceDueHours = t.balanceDueHours
        profile.contractGoverningState = t.governingState
    }

    /// "Deposit kept if more than 30 days out · 75% at 8–30 days · 100% at
    /// 7 days or fewer" — the one-line version for Key Terms and settings.
    func summary(hasDeposit: Bool) -> String {
        let t = normalized
        let early = hasDeposit
            ? "Deposit kept if more than \(t.cancelEarlyDays) days out"
            : "No fee if more than \(t.cancelEarlyDays) days out"
        return "\(early) · \(t.cancelMidPercent)% at \(t.cancelLateDays + 1)–\(t.cancelEarlyDays) days · \(t.cancelLatePercent)% at \(t.cancelLateDays) days or fewer"
    }
}
