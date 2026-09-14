import Foundation
import OSLog
import SwiftData

@MainActor
final class LocalReminderScheduler {
    static let shared = LocalReminderScheduler()

    private init() {}

    func refreshReminders(
        modelContext: ModelContext,
        activeBusinessID: UUID?
    ) async {
        guard let businessID = activeBusinessID else { return }

        do {
            let invoices = try modelContext.fetch(FetchDescriptor<Invoice>())
            let scopedInvoices = invoices.filter { $0.businessID == businessID }
            await NotificationManager.shared.syncInvoiceDueSoonReminders(
                businessID: businessID,
                invoices: scopedInvoices
            )
        } catch {
            SBWLog.notifications.problem("⚠️ Failed to fetch invoices for reminders: \(error)")
        }

        do {
            let jobs = try modelContext.fetch(FetchDescriptor<Job>())
            let scopedJobs = jobs.filter {
                guard $0.stage == .booked else { return false }
                guard $0.startDate > Date() else { return false }
                return $0.businessID == businessID
            }
            await NotificationManager.shared.syncJobComingUpReminders(
                businessID: businessID,
                jobs: scopedJobs
            )
        } catch {
            SBWLog.notifications.problem("⚠️ Failed to fetch jobs for reminders: \(error)")
        }
    }
}
