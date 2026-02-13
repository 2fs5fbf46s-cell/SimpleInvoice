import Foundation
import SwiftData

@Model
final class AppNotification {
    // CloudKit + SwiftData does NOT support @Attribute(.unique)
    // Keep an id, but enforce uniqueness in code (fetch-before-insert) instead.
    var id: String = UUID().uuidString

    var businessId: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var eventType: String = ""
    var deepLink: String? = nil
    var createdAtMs: Int = 0
    var readAtMs: Int? = nil
    var rawDataJson: String? = nil

    init(
        id: String = UUID().uuidString,
        businessId: UUID,
        title: String,
        body: String,
        eventType: String,
        deepLink: String? = nil,
        createdAtMs: Int,
        readAtMs: Int? = nil,
        rawDataJson: String? = nil
    ) {
        self.id = id
        self.businessId = businessId
        self.title = title
        self.body = body
        self.eventType = eventType
        self.deepLink = deepLink
        self.createdAtMs = createdAtMs
        self.readAtMs = readAtMs
        self.rawDataJson = rawDataJson
    }
}
