import Foundation
import SwiftData

/// Turns the backend's durable "estimate accepted" events into local state:
/// flips the local Invoice's estimateStatus (same as the old foreground-poll
/// path in EstimatePortalSyncService did), creates the Job via the existing
/// EstimateAcceptanceHandler, and activates any bundled draft Contract so it
/// becomes visible/signable in the portal. Nothing is generated server-side
/// for this — the device already holds the estimate and any bundled
/// contract, drafted before the estimate was ever sent (see
/// ContractCreation.create); the server only durably records that an
/// acceptance happened. Mirrors RecurringInvoicePullService's shape
/// (watermark, idempotent materialize) exactly.
///
/// Contract activation is split across the sync/async boundary deliberately:
/// `materialize` only flips the contract's local status (synchronous, no
/// network) so it stays directly testable without a background Task ever
/// outliving a test's in-memory container — that's what
/// PortalService.markContractSentAndIndex's own fire-and-forget `Task {}`
/// does, and it isn't safe to call from a synchronous function whose caller
/// may tear down its ModelContext right after. `pullAndMaterialize` (already
/// async) does the actual portal upload afterward, properly awaited via
/// PortalAutoSyncService.uploadContract — re-fetching by id rather than
/// holding the live object across the await, same as that function already
/// does internally.
@MainActor
enum EstimateAcceptancePullService {
    private static func watermarkKey(businessID: UUID) -> String {
        "sbw.estimateAcceptance.pullWatermarkMs.\(businessID.uuidString)"
    }

    static func pullAndMaterialize(context: ModelContext, businessID: UUID?) async {
        guard let businessID else { return }

        let defaults = UserDefaults.standard
        let key = watermarkKey(businessID: businessID)
        let watermarkMs = defaults.double(forKey: key)
        let since = watermarkMs > 0
            ? Date(timeIntervalSince1970: watermarkMs / 1000)
            : Date(timeIntervalSince1970: 0)

        let accepted: [AcceptedEstimateDTO]
        do {
            accepted = try await PortalBackend.shared.pullAcceptedEstimates(since: since)
        } catch {
            SBWLog.ui.problem("[EstimateAcceptance] pull failed: \(error)")
            return
        }

        guard !accepted.isEmpty else { return }

        var latestUpdatedAtMs = watermarkMs
        var materializedCount = 0
        var contractsToUpload: [UUID] = []
        for item in accepted {
            let result = materialize(item, businessID: businessID, context: context)
            if result.didChange { materializedCount += 1 }
            if let contractID = result.activatedContractID { contractsToUpload.append(contractID) }
            latestUpdatedAtMs = max(latestUpdatedAtMs, item.updatedAtMs)
        }

        if materializedCount > 0 {
            do {
                try context.save()
            } catch {
                SBWLog.ui.problem("[EstimateAcceptance] failed to save materialized state: \(error)")
            }
        }

        for contractID in contractsToUpload {
            _ = await PortalAutoSyncService.uploadContract(contractId: contractID, context: context)
        }

        // Advance the watermark even for entries this device chose to skip
        // (e.g. an estimate it doesn't have locally, from another device) —
        // same reasoning as RecurringInvoicePullService: the KV record is the
        // durable fact, reprocessing it later would never succeed
        // differently.
        defaults.set(latestUpdatedAtMs, forKey: key)
    }

    struct MaterializeResult {
        let didChange: Bool
        let activatedContractID: UUID?
    }

    /// Exposed at `internal` (not `private`), same reasoning as
    /// RecurringInvoicePullService.materialize — tests drive this directly
    /// with a hand-built DTO instead of mocking the network call.
    @discardableResult
    static func materialize(
        _ item: AcceptedEstimateDTO,
        businessID: UUID,
        context: ModelContext
    ) -> MaterializeResult {
        guard let estimateUUID = UUID(uuidString: item.estimateId) else {
            return MaterializeResult(didChange: false, activatedContractID: nil)
        }

        let estimate = (try? context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == estimateUUID })
        ))?.first
        guard let estimate, estimate.documentType == "estimate", estimate.businessID == businessID else {
            return MaterializeResult(didChange: false, activatedContractID: nil)
        }

        let wasAlreadyProcessed = estimate.estimateStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "accepted" && estimate.job != nil

        if !wasAlreadyProcessed {
            EstimateDecisionSync.setEstimateDecision(
                estimate: estimate,
                status: "accepted",
                decidedAtMs: Int64(item.decidedAtMs)
            )
            try? EstimateAcceptanceHandler.handleAccepted(estimate: estimate, context: context)
        }

        var activatedContractID: UUID?
        if let contract = linkedDraftContract(for: estimate, businessID: businessID, context: context) {
            contract.statusRaw = ContractStatus.sent.rawValue
            contract.portalNeedsUpload = true
            activatedContractID = contract.id
        }

        return MaterializeResult(
            didChange: !wasAlreadyProcessed || activatedContractID != nil,
            activatedContractID: activatedContractID
        )
    }

    /// A contract bundled with this estimate that's still sitting in
    /// .draft — old data may link via Contract.estimate, new data via
    /// Contract.invoice (see InvoiceDetailView.draftBundledContract).
    private static func linkedDraftContract(for estimate: Invoice, businessID: UUID, context: ModelContext) -> Contract? {
        let draftRaw = ContractStatus.draft.rawValue
        let descriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.businessID == businessID && $0.statusRaw == draftRaw }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        let estimateID = estimate.id
        return candidates.first { $0.invoice?.id == estimateID || $0.estimate?.id == estimateID }
    }
}
