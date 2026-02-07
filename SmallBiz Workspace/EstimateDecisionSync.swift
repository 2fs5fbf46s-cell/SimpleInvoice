import Foundation
import SwiftData

enum EstimateDecisionSync {
    struct DecisionPayload {
        let estimateId: UUID
        let businessId: UUID?
        let status: String
        let decidedAtMs: Int64
    }

    static func normalize(status: String) -> String? {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (s == "accepted" || s == "declined") ? s : nil
    }

    @MainActor
    static func upsertDecision(
        businessId: String,
        estimateId: String,
        status: String,
        decidedAt: Date,
        in context: ModelContext
    ) {
        let decidedAtMs = Int64((decidedAt.timeIntervalSince1970 * 1000.0).rounded())
        upsertDecision(
            businessId: businessId,
            estimateId: estimateId,
            status: status,
            decidedAtMs: decidedAtMs,
            in: context
        )
    }

    @MainActor
    static func upsertDecision(
        businessId: String,
        estimateId: String,
        status: String,
        decidedAtMs: Int64,
        in context: ModelContext
    ) {
        guard let normalized = normalize(status: status) else { return }
        let desc = FetchDescriptor<EstimateDecisionRecord>(
            predicate: #Predicate<EstimateDecisionRecord> { $0.estimateId == estimateId }
        )

        if let existing = try? context.fetch(desc).first {
            existing.businessId = businessId
            existing.status = normalized
            existing.decidedAtMs = decidedAtMs
            existing.updatedAt = .now
        } else {
            let record = EstimateDecisionRecord(
                businessId: businessId,
                estimateId: estimateId,
                status: normalized,
                decidedAtMs: decidedAtMs,
                updatedAt: .now
            )
            context.insert(record)
        }
    }

    @MainActor
    static func applyCachedDecisionIfAny(for estimate: Invoice, in context: ModelContext) {
        guard estimate.documentType == "estimate" else { return }
        let estimateId = estimate.id.uuidString

        let desc = FetchDescriptor<EstimateDecisionRecord>(
            predicate: #Predicate<EstimateDecisionRecord> { $0.estimateId == estimateId }
        )
        guard let record = try? context.fetch(desc).first else { return }
        guard record.businessId.isEmpty || record.businessId == estimate.businessID.uuidString else { return }

        setEstimateDecision(
            estimate: estimate,
            status: record.status,
            decidedAtMs: record.decidedAtMs
        )
    }

    @MainActor
    @discardableResult
    static func applyPendingDecisions(in context: ModelContext) -> Int {
        let desc = FetchDescriptor<EstimateDecisionRecord>(
            sortBy: [SortDescriptor(\EstimateDecisionRecord.updatedAt, order: .reverse)]
        )
        let records = (try? context.fetch(desc)) ?? []
        guard !records.isEmpty else { return 0 }

        let estimateDesc = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.documentType == "estimate" }
        )
        let estimates = (try? context.fetch(estimateDesc)) ?? []
        if estimates.isEmpty { return 0 }

        var applied = 0
        for estimate in estimates {
            guard let record = records.first(where: {
                $0.estimateId == estimate.id.uuidString &&
                ($0.businessId.isEmpty || $0.businessId == estimate.businessID.uuidString)
            }) else { continue }

            setEstimateDecision(
                estimate: estimate,
                status: record.status,
                decidedAtMs: record.decidedAtMs
            )
            applied += 1
        }

        try? context.save()
        return applied
    }

    @MainActor
    static func setEstimateDecision(estimate: Invoice, status: String, decidedAtMs: Int64) {
        guard let normalized = normalize(status: status) else { return }
        estimate.estimateStatus = normalized

        let date = Date(timeIntervalSince1970: Double(decidedAtMs) / 1000.0)
        if normalized == "accepted" {
            estimate.estimateAcceptedAt = date
            estimate.estimateDeclinedAt = nil
        } else if normalized == "declined" {
            estimate.estimateDeclinedAt = date
            estimate.estimateAcceptedAt = nil
        }
    }

    // Compatibility overload for existing call sites that pass Date.
    @MainActor
    static func setEstimateDecision(estimate: Invoice, status: String, decidedAt: Date) {
        let ms = Int64((decidedAt.timeIntervalSince1970 * 1000.0).rounded())
        setEstimateDecision(estimate: estimate, status: status, decidedAtMs: ms)
    }

    @MainActor
    static func parseDecision(from url: URL) -> DecisionPayload? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard
            let rawStatus = comps.queryItems?.first(where: { $0.name == "status" })?.value,
            let status = normalize(status: rawStatus)
        else { return nil }

        guard let estimateId = parseEstimateID(from: url) else { return nil }

        let businessId = comps.queryItems?
            .first(where: { $0.name == "businessId" })?
            .value
            .flatMap(UUID.init(uuidString:))

        let decidedAtRaw = comps.queryItems?.first(where: { $0.name == "decidedAtMs" })?.value
            ?? comps.queryItems?.first(where: { $0.name == "decidedAt" })?.value
        let decidedAtMs = parseDateMsFromQueryValue(decidedAtRaw) ?? Int64((Date().timeIntervalSince1970 * 1000.0).rounded())

        return DecisionPayload(
            estimateId: estimateId,
            businessId: businessId,
            status: status,
            decidedAtMs: decidedAtMs
        )
    }

    @MainActor
    static func handlePortalEstimateDecisionURL(_ url: URL, context: ModelContext) {
        guard let payload = parseDecision(from: url) else { return }

        let businessId = payload.businessId?.uuidString ?? ""
        upsertDecision(
            businessId: businessId,
            estimateId: payload.estimateId.uuidString,
            status: payload.status,
            decidedAtMs: payload.decidedAtMs,
            in: context
        )

        if let estimate = fetchEstimate(id: payload.estimateId, context: context),
           estimate.documentType == "estimate",
           (businessId.isEmpty || estimate.businessID.uuidString == businessId) {
            setEstimateDecision(
                estimate: estimate,
                status: payload.status,
                decidedAtMs: payload.decidedAtMs
            )
        }

        try? context.save()
        _ = applyPendingDecisions(in: context)
        PortalReturnRouter.shared.requestedEstimateID = payload.estimateId
    }

    @MainActor
    static func fetchEstimate(id: UUID, context: ModelContext) -> Invoice? {
        let desc = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.id == id && $0.documentType == "estimate" }
        )
        return try? context.fetch(desc).first
    }

    private static func parseEstimateID(from url: URL) -> UUID? {
        let parts = url.pathComponents.filter { $0 != "/" }

        if url.scheme?.lowercased() == "smallbizworkspace" {
            if let host = url.host, host.lowercased() == "estimate", let id = parts.first {
                return UUID(uuidString: id)
            }
            if parts.count >= 2, parts[0].lowercased() == "estimate" {
                return UUID(uuidString: parts[1])
            }
            if let host = url.host, host.lowercased() == "portal", parts.count >= 2, parts[0].lowercased() == "estimate" {
                return UUID(uuidString: parts[1])
            }
            return nil
        }

        if let idx = parts.firstIndex(where: { $0.lowercased() == "estimate" }), parts.count > idx + 1 {
            return UUID(uuidString: parts[idx + 1])
        }
        return nil
    }

    private static func parseDateMsFromQueryValue(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let intMs = Int64(trimmed) {
            return intMs > 1_000_000_000_000 ? intMs : intMs * 1000
        }

        if let doubleMs = Double(trimmed) {
            if doubleMs > 1_000_000_000_000 {
                return Int64(doubleMs.rounded())
            }
            return Int64((doubleMs * 1000.0).rounded())
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) {
            return Int64((d.timeIntervalSince1970 * 1000.0).rounded())
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        if let d = fallback.date(from: trimmed) {
            return Int64((d.timeIntervalSince1970 * 1000.0).rounded())
        }

        return nil
    }
}
