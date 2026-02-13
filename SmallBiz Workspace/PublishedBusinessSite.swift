import Foundation
import SwiftData

@Model
final class PublishedBusinessSite {
    var id: UUID = UUID()
    var businessID: UUID = UUID()

    var handle: String = ""
    var publicSiteDomain: String? = nil
    var appName: String = ""

    var heroImageLocalPath: String? = nil
    var heroImageRemoteUrl: String? = nil
    var aboutImageLocalPath: String? = nil
    var aboutImageRemoteUrl: String? = nil

    var services: [String] = []
    var aboutUs: String = ""
    var teamMembers: [String] = []

    // MARK: - Team Members (V2)
    /// Backward compatible V2 storage (JSON) so the live site can render name/title/photo.
    /// `teamMembers` remains as legacy fallback.
    var teamMembersV2Json: String = "[]"

    /// Draft-only: local file paths for team photos keyed by member id.
    /// Publish pipeline should upload these and fill `photoUrl`.
    var teamPhotoLocalPathByIdJson: String = "{}"

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
        publicSiteDomain: String? = nil,
        appName: String = "",
        heroImageLocalPath: String? = nil,
        heroImageRemoteUrl: String? = nil,
        aboutImageLocalPath: String? = nil,
        aboutImageRemoteUrl: String? = nil,
        services: [String] = [],
        aboutUs: String = "",
        teamMembers: [String] = [],
        teamMembersV2Json: String = "[]",
        teamPhotoLocalPathByIdJson: String = "{}",
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
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(publicSiteDomain ?? "")
        self.publicSiteDomain = normalizedDomain.isEmpty ? nil : normalizedDomain
        self.appName = appName
        self.heroImageLocalPath = heroImageLocalPath
        self.heroImageRemoteUrl = heroImageRemoteUrl
        self.aboutImageLocalPath = aboutImageLocalPath
        self.aboutImageRemoteUrl = aboutImageRemoteUrl
        self.services = services
        self.aboutUs = aboutUs
        self.teamMembers = teamMembers
        self.teamMembersV2Json = teamMembersV2Json
        self.teamPhotoLocalPathByIdJson = teamPhotoLocalPathByIdJson
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

    // MARK: - Team Members V2 (Computed)

    struct TeamMemberV2: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var title: String
        var photoUrl: String?

        init(id: String = UUID().uuidString, name: String = "", title: String = "", photoUrl: String? = nil) {
            self.id = id
            self.name = name
            self.title = title
            self.photoUrl = photoUrl
        }
    }

    /// Preferred team representation for publishing + website rendering.
    /// Stored as JSON to avoid SwiftData array-of-custom-type limitations.
    var teamMembersV2: [TeamMemberV2] {
        get {
            let raw = teamMembersV2Json.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TeamMemberV2].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                teamMembersV2Json = s
            } else {
                teamMembersV2Json = "[]"
            }
        }
    }

    /// Draft-only photo local path map: memberId -> file path.
    var teamPhotoLocalPathById: [String: String] {
        get {
            let raw = teamPhotoLocalPathByIdJson.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                teamPhotoLocalPathByIdJson = s
            } else {
                teamPhotoLocalPathByIdJson = "{}"
            }
        }
    }

    /// One-way helper: if V2 is empty but legacy names exist, create V2 rows.
    /// Call this when loading the draft into the customization UI.
    func migrateLegacyTeamMembersIfNeeded() {
        if !teamMembersV2.isEmpty { return }
        let legacy = teamMembers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !legacy.isEmpty else { return }
        teamMembersV2 = legacy.map { TeamMemberV2(name: $0, title: "", photoUrl: nil) }
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

    static func normalizePublicSiteDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let withoutProtocol: String
        if trimmed.hasPrefix("https://") {
            withoutProtocol = String(trimmed.dropFirst("https://".count))
        } else if trimmed.hasPrefix("http://") {
            withoutProtocol = String(trimmed.dropFirst("http://".count))
        } else {
            withoutProtocol = trimmed
        }

        let hostAndMaybePath = withoutProtocol.split(separator: "/").first.map(String.init) ?? ""
        let withoutPort = hostAndMaybePath.split(separator: ":").first.map(String.init) ?? ""
        let normalized = withoutPort.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
        return normalized
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
