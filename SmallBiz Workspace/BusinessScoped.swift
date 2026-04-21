//
//  BusinessScoped.swift
//  SmallBiz Workspace
//

import Foundation

enum BusinessScoped {
    static func effectiveBusinessID(explicit businessID: UUID?, activeBusinessID: UUID?) -> UUID? {
        businessID ?? activeBusinessID
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

extension Array where Element: BusinessOwned {
    func scoped(to businessID: UUID?) -> [Element] {
        guard let businessID else { return [] }
        return filter { $0.businessID == businessID }
    }
}
