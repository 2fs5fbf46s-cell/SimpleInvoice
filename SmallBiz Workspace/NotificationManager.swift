import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("⚠️ Notification authorization request failed: \(error)")
            return false
        }
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func scheduleTestLocalNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "SmallBiz Workspace"
        content.body = "Local notifications are working on this device."
        content.sound = .default
        content.badge = 1
        if let activeBusinessID = UserDefaults.standard.string(forKey: "activeBusinessID") {
            content.userInfo = [
                "event": "local_test",
                "businessId": activeBusinessID
            ]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "smallbiz.test.local.notification",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("⚠️ Failed to schedule local notification: \(error)")
        }
    }

    func clearPending() async {
        center.removeAllPendingNotificationRequests()
    }

    func syncInvoiceDueSoonReminders(
        businessID: UUID,
        invoices: [Invoice]
    ) async {
        let status = await getAuthorizationStatus()
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }

        let businessIDString = businessID.uuidString
        await clearManagedPending(for: businessIDString, kind: "invoice_due")
        let now = Date()
        let calendar = Calendar.current

        for invoice in invoices where !invoice.isPaid && invoice.documentType.lowercased() == "invoice" {
            let triggerDate = calendar.date(byAdding: .day, value: -2, to: invoice.dueDate) ?? invoice.dueDate
            guard triggerDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Invoice due soon"
            content.body = "Invoice \(invoice.invoiceNumber) is due in 2 days."
            content.sound = .default
            content.userInfo = [
                "event": "invoice_due_soon",
                "businessId": businessIDString,
                "invoiceId": invoice.id.uuidString
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(kind: "invoice_due", businessID: businessIDString, itemID: invoice.id.uuidString),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("⚠️ Failed to schedule invoice reminder for \(invoice.id): \(error)")
            }
        }
    }

    func syncBookingComingUpReminders(
        businessID: UUID,
        bookings: [Booking]
    ) async {
        let status = await getAuthorizationStatus()
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }

        let businessIDString = businessID.uuidString
        await clearManagedPending(for: businessIDString, kind: "booking_upcoming")
        let now = Date()
        let calendar = Calendar.current

        for booking in bookings {
            let triggerDate = calendar.date(byAdding: .hour, value: -24, to: booking.startDate) ?? booking.startDate
            guard triggerDate > now else { continue }

            let title = booking.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let reminderTitle = title.isEmpty ? "Booking reminder" : title
            let content = UNMutableNotificationContent()
            content.title = "Booking coming up"
            content.body = "\(reminderTitle) starts in about 24 hours."
            content.sound = .default
            content.userInfo = [
                "event": "booking_coming_up",
                "businessId": businessIDString
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(kind: "booking_upcoming", businessID: businessIDString, itemID: booking.id.uuidString),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("⚠️ Failed to schedule booking reminder for \(booking.id): \(error)")
            }
        }
    }

    private func reminderIdentifier(kind: String, businessID: String, itemID: String) -> String {
        "smallbiz.\(kind).\(businessID).\(itemID)"
    }

    private func clearManagedPending(for businessID: String, kind: String) async {
        let prefix = "smallbiz.\(kind).\(businessID)."
        let requests = await pendingRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
