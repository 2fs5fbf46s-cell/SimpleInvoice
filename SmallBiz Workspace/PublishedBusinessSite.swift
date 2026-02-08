import Foundation
import SwiftData

@Model
final class PublishedBusinessSite {
    var id: UUID = UUID()
    var businessID: UUID = UUID()

    var handle: String = ""
    var appName: String = ""

    var heroImageLocalPath: String? = nil
    var heroImageRemoteUrl: String? = nil
    var aboutImageLocalPath: String? = nil
    var aboutImageRemoteUrl: String? = nil

    var services: [String] = []
    var aboutUs: String = ""
    var teamMembers: [String] = []

    var galleryLocalPaths: [String] = []
    var galleryRemoteUrls: [String] = []

    var updatedAt: Date = Foundation.Date()
    var lastPublishedAt: Date? = nil

    /// draft | queued | publishing | published | error
    var publishStatus: String = PublishStatus.draft.rawValue
    var lastPublishError: String? = nil
    var needsSync: Bool = false

    init(
        id: UUID = UUID(),
        businessID: UUID,
        handle: String = "",
        appName: String = "",
        heroImageLocalPath: String? = nil,
        heroImageRemoteUrl: String? = nil,
        aboutImageLocalPath: String? = nil,
        aboutImageRemoteUrl: String? = nil,
        services: [String] = [],
        aboutUs: String = "",
        teamMembers: [String] = [],
        galleryLocalPaths: [String] = [],
        galleryRemoteUrls: [String] = [],
        updatedAt: Date = Foundation.Date(),
        lastPublishedAt: Date? = nil,
        publishStatus: String = PublishStatus.draft.rawValue,
        lastPublishError: String? = nil,
        needsSync: Bool = false
    ) {
        self.id = id
        self.businessID = businessID
        self.handle = PublishedBusinessSite.normalizeHandle(handle)
        self.appName = appName
        self.heroImageLocalPath = heroImageLocalPath
        self.heroImageRemoteUrl = heroImageRemoteUrl
        self.aboutImageLocalPath = aboutImageLocalPath
        self.aboutImageRemoteUrl = aboutImageRemoteUrl
        self.services = services
        self.aboutUs = aboutUs
        self.teamMembers = teamMembers
        self.galleryLocalPaths = galleryLocalPaths
        self.galleryRemoteUrls = galleryRemoteUrls
        self.updatedAt = updatedAt
        self.lastPublishedAt = lastPublishedAt
        self.publishStatus = publishStatus
        self.lastPublishError = lastPublishError
        self.needsSync = needsSync
    }

    var status: PublishStatus {
        PublishStatus(rawValue: publishStatus) ?? .draft
    }

    static func normalizeHandle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let mapped = trimmed.unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            if scalar == " " || scalar == "_" || scalar == "." {
                return "-"
            }
            return ""
        }.joined()

        let parts = mapped.split(separator: "-").filter { !$0.isEmpty }
        return parts.joined(separator: "-")
    }

    static func splitLines(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func joinLines(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum PublishStatus: String, CaseIterable {
    case draft
    case queued
    case publishing
    case published
    case error
}
