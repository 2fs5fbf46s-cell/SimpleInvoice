//
//  ContractStatusFilter.swift
//  SmallBiz Workspace
//

import Foundation

/// Shared filter used by ContractsHomeView + ContractsListView.
enum ContractStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case sent = "Sent"
    case signed = "Signed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    func matches(_ contract: Contract) -> Bool {
        switch self {
        case .all: return true
        case .draft: return contract.status == .draft
        case .sent: return contract.status == .sent
        case .signed: return contract.status == .signed
        case .cancelled: return contract.status == .cancelled
        }
    }
}
