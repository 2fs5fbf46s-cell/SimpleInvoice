import Foundation
import SwiftData

@MainActor
enum EstimateAcceptanceHandler {
    static func handleAccepted(estimate: Invoice, context: ModelContext) throws {
        guard estimate.documentType == "estimate" else { return }

        let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status == "accepted" else { return }

        if estimate.job != nil { return }

        let clientName = estimate.client?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeClient = (clientName?.isEmpty == false) ? clientName! : "Client"
        let estimateNumber = estimate.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeEstimateNumber = estimateNumber.isEmpty ? String(estimate.id.uuidString.prefix(8)) : estimateNumber
        let title = "Job - \(safeClient) (\(safeEstimateNumber))"

        let job = Job(
            businessID: estimate.businessID,
            clientID: estimate.client?.id,
            title: title,
            notes: "Created from estimate \(safeEstimateNumber)",
            startDate: estimate.issueDate,
            endDate: estimate.dueDate,
            locationName: estimate.client?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            latitude: nil,
            longitude: nil,
            status: "scheduled",
            sourceEstimateId: estimate.id.uuidString
        )
        // The estimate's dates are when it was written and how long it was
        // valid — not when the work happens. Wait for a real date.
        job.needsScheduling = true

        context.insert(job)
        estimate.job = job
        try context.save()
    }
}
