//
//  RecurringScheduleSync.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Keeps the server's copy of each recurring schedule in step with the
/// device, since the server is what bills the client.
///
/// It used to fire-and-forget: a failed upload was never retried (the
/// schedule "saved" but never generated), a failed delete left the server
/// billing a schedule the owner had removed, and the device never learned
/// the server had moved the next run forward, so the next edit sent the old
/// date back and the client got a second invoice.
@MainActor
enum RecurringScheduleSync {
    private static let pendingDeletesKey = "sbw.recurring.pendingDeletes"

    /// Uploads the schedule and takes the server's dates back. Returns why
    /// it failed, or nil; a failed upload is retried by `retryPending`.
    @discardableResult
    static func push(_ schedule: RecurringInvoiceSchedule, context: ModelContext) async -> String? {
        let clientID = schedule.clientID
        let client = try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientID })).first
        guard let client else { return nil }
        do {
            let result = try await PortalBackend.shared.upsertRecurringSchedule(schedule, clientEmail: client.email)
            if let next = result.nextRunAt, next != schedule.nextRunAt { schedule.nextRunAt = next }
            if let last = result.lastGeneratedAt { schedule.lastGeneratedAt = last }
            schedule.needsBackendSync = false
            try? context.save()
            return nil
        } catch {
            schedule.needsBackendSync = true
            try? context.save()
            return error.localizedDescription
        }
    }

    /// Removes the schedule here and on the server. If the server can't be
    /// reached, the delete is kept and retried until it goes through, so the
    /// client stops being billed.
    static func delete(_ schedule: RecurringInvoiceSchedule, context: ModelContext) {
        let businessID = schedule.businessID
        let entry = "\(businessID.uuidString)|\(schedule.id.uuidString)"
        var pending = pendingDeletes
        pending.insert(entry)
        pendingDeletes = pending
        context.delete(schedule)
        try? context.save()
        Task { await flushDeletes(businessID: businessID) }
    }

    /// Deletes and uploads that didn't reach the server, and dates the
    /// server has moved, for the business signed in now (the server takes
    /// the active business's sign-in).
    static func retryPending(context: ModelContext, businessID: UUID?) async {
        // Every business's queued deletes, each with its own sign-in: a
        // deleted business is never active again.
        let queuedBusinesses = Set(pendingDeletes.compactMap { UUID(uuidString: String($0.prefix(while: { $0 != "|" }))) })
        for queued in queuedBusinesses {
            await flushDeletes(businessID: queued)
        }
        guard let businessID else { return }
        // Also any whose next run has passed: the server has run it and moved
        // the date on, and pushing is how the device reads that back (the
        // server keeps its later date).
        let now = Date.now
        let stale = (try? context.fetch(FetchDescriptor<RecurringInvoiceSchedule>(
            predicate: #Predicate { $0.businessID == businessID && ($0.needsBackendSync || $0.nextRunAt < now) }
        ))) ?? []
        for schedule in stale {
            await push(schedule, context: context)
        }
    }

    static func flushDeletes(businessID: UUID) async {
        let prefix = "\(businessID.uuidString)|"
        for entry in pendingDeletes where entry.hasPrefix(prefix) {
            guard let id = UUID(uuidString: String(entry.dropFirst(prefix.count))) else {
                pendingDeletes.remove(entry)
                continue
            }
            let token = BusinessTokenStore.shared.token(for: businessID)
            if (try? await PortalBackend.shared.deleteRecurringSchedule(scheduleId: id, businessToken: token)) != nil {
                pendingDeletes.remove(entry)
            }
        }
    }

    private static var pendingDeletes: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: pendingDeletesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: pendingDeletesKey) }
    }
}
