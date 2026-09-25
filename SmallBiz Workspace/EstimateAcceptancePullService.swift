import Foundation
import SwiftData

/// Turns the backend's durable estimate-decision events into local state —
/// the only path by which a client's portal decision reaches the device
/// (push-triggered, plus a pull on every launch/foreground as the fallback).
/// A decline just flips the local estimateStatus. An acceptance also creates
/// the Job via the existing EstimateAcceptanceHandler, and activates any
/// bundled draft Contract so it becomes visible/signable in the portal. Nothing is generated server-side
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

        let decisions: [EstimateDecisionDTO]
        do {
            decisions = try await PortalBackend.shared.pullEstimateDecisions(since: since)
        } catch {
            SBWLog.ui.problem("[EstimateAcceptance] pull failed: \(error)")
            return
        }

        guard !decisions.isEmpty else { return }

        var latestUpdatedAtMs = watermarkMs
        var materializedCount = 0
        var contractsToUpload: [UUID] = []
        var invoicesToUpload: [UUID] = []
        // Oldest first: an estimate decided twice (accepted, then declined)
        // must end on the later decision.
        for item in decisions.sorted(by: { $0.updatedAtMs < $1.updatedAtMs }) {
            let result = materialize(item, businessID: businessID, context: context)
            if result.didChange { materializedCount += 1 }
            if let contractID = result.activatedContractID { contractsToUpload.append(contractID) }
            if let depositInvoiceID = result.depositInvoiceID { invoicesToUpload.append(depositInvoiceID) }
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
        for invoiceID in invoicesToUpload {
            _ = await PortalAutoSyncService.uploadInvoice(invoiceId: invoiceID, context: context)
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
        let depositInvoiceID: UUID?
    }

    /// Exposed at `internal` (not `private`), same reasoning as
    /// RecurringInvoicePullService.materialize — tests drive this directly
    /// with a hand-built DTO instead of mocking the network call.
    @discardableResult
    static func materialize(
        _ item: EstimateDecisionDTO,
        businessID: UUID,
        context: ModelContext
    ) -> MaterializeResult {
        let unchanged = MaterializeResult(didChange: false, activatedContractID: nil, depositInvoiceID: nil)
        guard let estimateUUID = UUID(uuidString: item.estimateId) else { return unchanged }

        let estimate = (try? context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == estimateUUID })
        ))?.first
        guard let estimate, estimate.documentType == "estimate", estimate.businessID == businessID else {
            return unchanged
        }

        let localStatus = estimate.estimateStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch item.status {
        case "accepted":
            break
        case "declined":
            // Only the status moves. A Job already created by an earlier
            // acceptance is left alone — deleting the owner's work on a
            // client's change of mind isn't this sync's call.
            guard localStatus != "declined" else { return unchanged }
            EstimateDecisionSync.setEstimateDecision(
                estimate: estimate,
                status: "declined",
                decidedAtMs: Int64(item.decidedAtMs)
            )
            return MaterializeResult(didChange: true, activatedContractID: nil, depositInvoiceID: nil)
        default:
            return unchanged
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
        var depositInvoiceID: UUID?
        if let contract = linkedDraftContract(for: estimate, businessID: businessID, context: context) {
            contract.statusRaw = ContractStatus.sent.rawValue
            contract.portalNeedsUpload = true
            activatedContractID = contract.id

            if let depositCents = contract.depositAmountCents, let job = estimate.job {
                depositInvoiceID = createDepositInvoiceIfNeeded(
                    depositCents: depositCents,
                    contract: contract,
                    job: job,
                    estimate: estimate,
                    context: context
                )
            }
        }

        return MaterializeResult(
            didChange: !wasAlreadyProcessed || activatedContractID != nil || depositInvoiceID != nil,
            activatedContractID: activatedContractID,
            depositInvoiceID: depositInvoiceID
        )
    }

    /// Deposit tracking, decoupled from signing: creates an ordinary local
    /// invoice for the configured deposit and links it to the Job. Never
    /// blocks or is blocked by contract activation above — a deposit that
    /// fails to create here doesn't stop the client from being able to
    /// sign; it's a soft reminder, not a gate (see Job.depositAmountCents).
    /// Idempotent via job.depositInvoiceId.
    private static func createDepositInvoiceIfNeeded(
        depositCents: Int,
        contract: Contract,
        job: Job,
        estimate: Invoice,
        context: ModelContext
    ) -> UUID? {
        guard job.depositInvoiceId == nil else { return nil }
        guard let client = estimate.client else { return nil }

        let jobBusinessID = job.businessID
        let profile = (try? context.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate<BusinessProfile> { $0.businessID == jobBusinessID })
        ))?.first
        let invoiceNumber = profile.map { InvoiceNumberGenerator.consumeNextNumber(profile: $0) }
            ?? "DEP-\(String(job.id.uuidString.prefix(8)))"

        let deposit = Invoice(
            businessID: job.businessID,
            invoiceNumber: invoiceNumber,
            issueDate: .now,
            dueDate: job.startDate,
            paymentTerms: "Deposit due before work starts",
            notes: "Deposit for \(contract.title.isEmpty ? "contract" : contract.title)",
            thankYou: profile?.defaultThankYou ?? "",
            termsAndConditions: "",
            taxRate: 0,
            discountAmount: 0,
            isPaid: false,
            documentType: "invoice",
            client: client,
            job: job,
            items: [LineItem(itemDescription: "Deposit", quantity: 1, unitPrice: Double(depositCents) / 100.0)]
        )
        deposit.sourceContractId = contract.id.uuidString
        deposit.portalNeedsUpload = true

        context.insert(deposit)

        job.depositAmountCents = depositCents
        job.depositInvoiceId = deposit.id.uuidString

        return deposit.id
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
