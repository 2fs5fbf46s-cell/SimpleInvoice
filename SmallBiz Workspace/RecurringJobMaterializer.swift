import Foundation
import SwiftData

/// Client-side-only recurrence for Jobs. Recurring invoices are generated
/// server-side (see RecurringInvoicePullService) because a missed invoice is
/// a real financial miss even if the owner's phone is off for weeks. A
/// repeating Job has no such stakes — nothing client-facing depends on it
/// existing by a specific instant — so this just checks due occurrences
/// whenever the app comes to the foreground (SmallBiz WorkspaceApp's
/// runWorkspaceServices), the same trigger point as other local-only work
/// like LocalReminderScheduler.
enum RecurringJobMaterializer {
    @MainActor
    static func materializeDueOccurrences(context: ModelContext, businessID: UUID) {
        let descriptor = FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID })
        guard let jobs = try? context.fetch(descriptor) else { return }

        let now = Date()
        let due = jobs.filter { job in
            job.recurringCadence != nil && (job.recurringNextOccurrenceAt ?? .distantFuture) <= now
        }
        guard !due.isEmpty else { return }

        var changed = false
        for job in due {
            guard let cadence = job.recurringCadence, let nextAt = job.recurringNextOccurrenceAt else { continue }

            // Idempotency: if a Job has already been generated from this one
            // (e.g. a previous launch got partway through and saved before
            // clearing the cadence), just finish handing off the chain
            // rather than generating a duplicate.
            if jobs.contains(where: { $0.recurringParentJobID == job.id }) {
                job.recurringCadenceRaw = nil
                job.recurringNextOccurrenceAt = nil
                changed = true
                continue
            }

            let duration = job.endDate.timeIntervalSince(job.startDate)
            let next = Job(
                businessID: job.businessID,
                clientID: job.clientID,
                title: job.title,
                notes: job.notes,
                startDate: nextAt,
                endDate: nextAt.addingTimeInterval(max(duration, 0)),
                locationName: job.locationName
                // latitude/longitude, measurements and attachments are
                // deliberately not carried forward — those belong to one
                // specific visit, captured fresh each time.
            )
            next.recurringCadenceRaw = cadence.rawValue
            next.recurringNextOccurrenceAt = cadence.advancing(from: nextAt)
            next.recurringParentJobID = job.id
            context.insert(next)

            // Hand the chain off; this Job is now history, not the head.
            job.recurringCadenceRaw = nil
            job.recurringNextOccurrenceAt = nil
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}
