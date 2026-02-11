import Foundation
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
            print("⚠️ Failed to fetch invoices for reminders: \(error)")
        }

        do {
            let bookings = try modelContext.fetch(FetchDescriptor<Booking>())
            let scopedBookings = bookings.filter {
                guard $0.status.lowercased() == "scheduled" else { return false }
                guard $0.startDate > Date() else { return false }
                return $0.client?.businessID == businessID
            }
            await NotificationManager.shared.syncBookingComingUpReminders(
                businessID: businessID,
                bookings: scopedBookings
            )
        } catch {
            print("⚠️ Failed to fetch bookings for reminders: \(error)")
        }
    }
}
