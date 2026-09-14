//
//  BusinessScoped.swift
//  SmallBiz Workspace
//

import Foundation

enum BusinessScoped {
    static func effectiveBusinessID(explicit businessID: UUID?, activeBusinessID: UUID?) -> UUID? {
        businessID ?? activeBusinessID
    }

    /// Stands in for "no business selected" inside a `#Predicate`.
    ///
    /// A predicate has to be built at `init`, before we know whether a business is
    /// active, and it needs a concrete UUID either way. This one belongs to no
    /// record, so the fetch returns nothing — which is what an unscoped view
    /// should show. It must be a constant rather than a fresh `UUID()`: a new
    /// value on every init would give the query a new identity each render and
    /// re-fetch continuously.
    static let unmatchableBusinessID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// The id to filter a fetch by, safe to embed in a `#Predicate`.
    static func queryBusinessID(_ businessID: UUID?) -> UUID {
        businessID ?? unmatchableBusinessID
    }
}

protocol BusinessOwned {
    var businessID: UUID { get }
}

extension Client: BusinessOwned {}
extension Invoice: BusinessOwned {}
extension Job: BusinessOwned {}
extension Contract: BusinessOwned {}
extension BusinessProfile: BusinessOwned {}
extension Expense: BusinessOwned {}
extension RecurringInvoiceSchedule: BusinessOwned {}

extension Array where Element: BusinessOwned {
    func scoped(to businessID: UUID?) -> [Element] {
        guard let businessID else { return [] }
        return filter { $0.businessID == businessID }
    }
}
