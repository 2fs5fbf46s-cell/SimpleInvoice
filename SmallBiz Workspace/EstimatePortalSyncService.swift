import Foundation
import SwiftData
import OSLog

enum EstimatePortalSyncService {
    private static let log = Logger(subsystem: "com.javonfreeman.smallbizworkspace", category: "EstimateSync")

    @MainActor
    static func sync(context: ModelContext) async {
        await sync(context: context, maxCount: 40)
    }

    @MainActor
    private static func sync(context: ModelContext, maxCount: Int) async {
        // Always try to apply locally-cached decisions first.
        let appliedBefore = EstimateDecisionSync.applyPendingDecisions(in: context)

        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.documentType == "estimate" },
            sortBy: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )

        let estimates = ((try? context.fetch(descriptor)) ?? [])
            .filter { estimate in
                let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return (status == "sent" || status == "draft") && (estimate.client?.portalEnabled == true)
            }
            .prefix(maxCount)

        var checked = 0
        var updated = 0
        var failed = 0

        for estimate in estimates {
            checked += 1
            do {
                let remote = try await PortalBackend.shared.fetchEstimateStatus(
                    businessId: estimate.businessID.uuidString,
                    estimateId: estimate.id.uuidString
                )

                let local = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if remote.status != local {
                    EstimateDecisionSync.setEstimateDecision(
                        estimate: estimate,
                        status: remote.status,
                        decidedAt: remote.decidedAt ?? .now
                    )
                    if remote.status == "accepted" {
                        try? EstimateAcceptanceHandler.handleAccepted(estimate: estimate, context: context)
                    }
                    updated += 1
                    try? context.save()
                }
            } catch {
                // Offline / transient failures should not mutate local state.
                failed += 1
                #if DEBUG
                log.debug("Estimate sync fetch failed id=\(estimate.id.uuidString, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
                #endif
                continue
            }
        }

        // Replay local queue after network attempts too.
        let appliedAfter = EstimateDecisionSync.applyPendingDecisions(in: context)

        #if DEBUG
        log.debug("Estimate sync run checked=\(checked, privacy: .public) updated=\(updated, privacy: .public) failed=\(failed, privacy: .public) pendingBefore=\(appliedBefore, privacy: .public) pendingAfter=\(appliedAfter, privacy: .public)")
        #else
        if updated > 0 || failed > 0 || appliedBefore > 0 || appliedAfter > 0 {
            log.info("Estimate sync checked=\(checked, privacy: .public) updated=\(updated, privacy: .public) failed=\(failed, privacy: .public)")
        }
        #endif
    }
}
