import Foundation
import SwiftData

@Model
final class EstimateDecisionRecord {
    var id: UUID = UUID()
    var businessId: String = ""
    var estimateId: String = ""
    var status: String = "" // accepted | declined
    var decidedAtMs: Int64 = 0
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        businessId: String,
        estimateId: String,
        status: String,
        decidedAtMs: Int64,
        updatedAt: Date = Foundation.Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.estimateId = estimateId
        self.status = status
        self.decidedAtMs = decidedAtMs
        self.updatedAt = updatedAt
    }
}
