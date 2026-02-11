import Foundation
import SwiftData

@MainActor
final class NotificationInboxService {
    static let shared = NotificationInboxService()

    private let defaults: UserDefaults
    private let refreshKey = "notificationInboxNeedsRefresh"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markNeedsRefresh() {
        defaults.set(true, forKey: refreshKey)
    }

    func refreshIfNeeded(modelContext: ModelContext, businessId: UUID?) async {
        guard defaults.bool(forKey: refreshKey) else { return }
        guard let businessId else { return }
        do {
            _ = try await refresh(modelContext: modelContext, businessId: businessId)
            defaults.set(false, forKey: refreshKey)
        } catch {
            print("⚠️ Inbox refresh failed: \(error)")
        }
    }

    @discardableResult
    func refresh(modelContext: ModelContext, businessId: UUID) async throws -> Int {
        let response = try await PortalBackend.shared.fetchNotifications(businessId: businessId)
        let existing = try modelContext.fetch(FetchDescriptor<AppNotification>())

        for dto in response.items {
            guard let dtoBusinessID = UUID(uuidString: dto.businessId), dtoBusinessID == businessId else { continue }

            if let existingItem = existing.first(where: { $0.businessId == businessId && $0.id == dto.notificationId }) {
                existingItem.title = dto.title
                existingItem.body = dto.body
                existingItem.eventType = dto.eventType
                existingItem.deepLink = dto.deepLink
                existingItem.createdAtMs = dto.createdAtMs
                existingItem.readAtMs = dto.readAtMs
                existingItem.rawDataJson = dto.rawDataJson
            } else {
                let created = AppNotification(
                    id: dto.notificationId,
                    businessId: businessId,
                    title: dto.title,
                    body: dto.body,
                    eventType: dto.eventType,
                    deepLink: dto.deepLink,
                    createdAtMs: dto.createdAtMs,
                    readAtMs: dto.readAtMs,
                    rawDataJson: dto.rawDataJson
                )
                modelContext.insert(created)
            }
        }

        try modelContext.save()
        return response.unreadCount
    }

    func markRead(
        _ notification: AppNotification,
        modelContext: ModelContext,
        businessId: UUID
    ) async {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        if notification.readAtMs == nil {
            notification.readAtMs = nowMs
            try? modelContext.save()
        }

        do {
            try await PortalBackend.shared.markNotificationRead(
                businessId: businessId,
                notificationId: notification.id
            )
        } catch {
            print("⚠️ Failed to mark notification read remotely: \(error)")
        }
    }

    func markAllRead(
        notifications: [AppNotification],
        modelContext: ModelContext,
        businessId: UUID
    ) async {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        for item in notifications where item.readAtMs == nil {
            item.readAtMs = nowMs
        }
        try? modelContext.save()

        do {
            try await PortalBackend.shared.markAllNotificationsRead(businessId: businessId)
        } catch {
            print("⚠️ Failed to mark all notifications read remotely: \(error)")
        }
    }

    static func payloadSuggestsInboxRefresh(_ userInfo: [AnyHashable: Any]) -> Bool {
        func hasValue(_ key: String) -> Bool {
            guard let value = userInfo[key] else { return false }
            let raw = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return !raw.isEmpty
        }

        return hasValue("notificationId")
            || hasValue("deepLink")
            || hasValue("eventType")
            || hasValue("event")
    }
}
