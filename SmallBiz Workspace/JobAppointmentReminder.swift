import Foundation

/// Whether a Job qualifies for the backend's 24h-before appointment-reminder
/// email. Pulled out as a pure predicate — no network, no SwiftData context
/// — so it's directly testable, mirroring
/// `PortalBackend.isContractReadyForDirectory`.
enum JobAppointmentReminderEligibility {
    static func isEligible(job: Job, client: Client?) -> Bool {
        guard !job.needsScheduling else { return false }
        guard let client else { return false }
        return !client.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
