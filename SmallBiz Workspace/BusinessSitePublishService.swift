import Foundation
import SwiftData
import Network
import UIKit

@MainActor
final class BusinessSitePublishService {
    static let shared = BusinessSitePublishService()

    private var monitor: NWPathMonitor?
    private var isNetworkReachable = true
    private var inFlightSiteIDs: Set<UUID> = []
    private var syncContext: ModelContext?

    private let maxPublicImageDimension: CGFloat = 1600
    private let targetJPEGQuality: CGFloat = 0.72
    private let maxUploadBytes: Int = 4_500_000

    private init() {}

    @MainActor
    private static func handleNetworkUpdateOnMain(isReachable: Bool) {
        BusinessSitePublishService.shared.handleNetworkPathUpdate(isReachable: isReachable)
    }

    func startMonitoring(context: ModelContext) {
        guard monitor == nil else { return }
        self.syncContext = context

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "BusinessSitePublishService.Network")
        monitor.pathUpdateHandler = { path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor in
                BusinessSitePublishService.handleNetworkUpdateOnMain(isReachable: satisfied)
            }
        }

        monitor.start(queue: queue)
        self.monitor = monitor
    }

    private func handleNetworkPathUpdate(isReachable: Bool) {
        let becameReachable = !self.isNetworkReachable && isReachable
        self.isNetworkReachable = isReachable

        if becameReachable, let ctx = self.syncContext {
            Task { @MainActor in
                await self.syncQueuedSites(context: ctx)
            }
        }
    }

    func draft(for businessID: UUID, context: ModelContext) -> PublishedBusinessSite {
        if let existing = fetchDraft(for: businessID, context: context) {
            return existing
        }

        let created = PublishedBusinessSite(businessID: businessID)
        context.insert(created)
        try? context.save()
        return created
    }

    func queuePublish(
        draft: PublishedBusinessSite,
        profile: BusinessProfile,
        business: Business?,
        context: ModelContext
    ) async throws {
        let normalizedHandle = PublishedBusinessSite.normalizeHandle(draft.handle)
        guard !normalizedHandle.isEmpty else {
            throw BusinessSitePublishError.invalidHandle
        }

        draft.handle = normalizedHandle
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(draft.publicSiteDomain ?? "")
        draft.publicSiteDomain = normalizedDomain.isEmpty ? nil : normalizedDomain
        draft.appName = resolvedAppName(draft: draft, profile: profile, business: business)
        draft.services = draft.services.isEmpty ? PublishedBusinessSite.splitLines(profile.catalogCategoriesText) : draft.services
        if draft.aboutUs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.aboutUs = profile.defaultThankYou.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if draft.heroImageLocalPath == nil, let logoData = profile.logoData {
            draft.heroImageLocalPath = try? persistTemporaryAsset(
                data: logoData,
                businessID: draft.businessID,
                prefix: "public-site-hero",
                fileExtension: "png"
            )
        }

        draft.updatedAt = .now
        draft.publishStatus = PublishStatus.queued.rawValue
        draft.needsSync = true
        draft.lastPublishError = nil
        try? context.save()

        await attemptPublishIfPossible(siteID: draft.id, context: context)
    }

    func syncQueuedSites(context: ModelContext) async {
        let all = (try? context.fetch(FetchDescriptor<PublishedBusinessSite>())) ?? []
        let pending = all.filter { $0.needsSync }

        for site in pending {
            await attemptPublishIfPossible(siteID: site.id, context: context)
        }
    }

    func saveDraftEdits(_ draft: PublishedBusinessSite, context: ModelContext) {
        draft.handle = PublishedBusinessSite.normalizeHandle(draft.handle)
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(draft.publicSiteDomain ?? "")
        draft.publicSiteDomain = normalizedDomain.isEmpty ? nil : normalizedDomain
        draft.updatedAt = .now
        if draft.publishStatus == PublishStatus.published.rawValue {
            draft.publishStatus = PublishStatus.draft.rawValue
        }
        try? context.save()
    }

    func publishPublicSite(site: PublishedBusinessSite, context: ModelContext) async {
        site.publishStatus = PublishStatus.publishing.rawValue
        site.lastPublishError = nil
        site.updatedAt = .now
        try? context.save()

        do {
            try await uploadAssetsIfNeeded(site: site)

            let normalizedTeam = site.teamMembersV2
                .map {
                    PublishedBusinessSite.TeamMemberV2(
                        id: $0.id,
                        name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        photoUrl: $0.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.name.isEmpty }

            site.teamMembersV2 = normalizedTeam
            site.teamMembers = normalizedTeam.map { $0.name }

            let teamV2Payload = normalizedTeam.map {
                PublicSiteUpsertPayload.TeamMemberV2Payload(
                    id: $0.id,
                    name: $0.name,
                    title: $0.title,
                    photoUrl: $0.photoUrl
                )
            }

            let payload = PublicSiteUpsertPayload(
                appName: site.appName,
                heroUrl: site.heroImageRemoteUrl,
                aboutUrl: site.aboutImageRemoteUrl,
                services: site.services,
                aboutUs: site.aboutUs,
                team: site.teamMembers,
                teamV2: teamV2Payload,
                galleryUrls: site.galleryRemoteUrls,
                updatedAtMs: Int(site.updatedAt.timeIntervalSince1970 * 1000)
            )

            _ = try await PortalBackend.shared.upsertPublicSite(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                payload: payload
            )

            if let domain = site.publicSiteDomain?.trimmingCharacters(in: .whitespacesAndNewlines),
               !domain.isEmpty {
                var domainWarning: String?
                do {
                    try await PortalBackend.shared.upsertPublicSiteDomainMapping(
                        domain: domain,
                        businessId: site.businessID.uuidString,
                        handle: site.handle,
                        includeWww: site.includeWww
                    )
                } catch {
                    #if DEBUG
                    print("⚠️ Public site domain mapping failed: \(error.localizedDescription)")
                    #endif
                    if case PortalBackendError.http(let code, _, _) = error, code == 409 {
                        domainWarning = "This domain is already connected to another business."
                    } else {
                        domainWarning = "domain mapping failed: \(error.localizedDescription)"
                    }
                }
                if let domainWarning, !domainWarning.isEmpty {
                    site.lastPublishError = domainWarning
                }
            }

            site.publishStatus = PublishStatus.published.rawValue
            site.lastPublishedAt = .now
            site.needsSync = false
            if site.lastPublishError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                site.lastPublishError = nil
            }
            try? context.save()
        } catch {
            site.publishStatus = PublishStatus.error.rawValue
            site.lastPublishError = error.localizedDescription
            site.needsSync = true
            try? context.save()
        }
    }

    private func fetchDraft(for businessID: UUID, context: ModelContext) -> PublishedBusinessSite? {
        let all = (try? context.fetch(FetchDescriptor<PublishedBusinessSite>())) ?? []
        return all.first(where: { $0.businessID == businessID })
    }

    private func resolvedAppName(
        draft: PublishedBusinessSite,
        profile: BusinessProfile,
        business: Business?
    ) -> String {
        let explicit = draft.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let businessName = business?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !businessName.isEmpty { return businessName }

        let profileName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileName.isEmpty { return profileName }

        return "SmallBiz Workspace"
    }

    private func attemptPublishIfPossible(siteID: UUID, context: ModelContext) async {
        guard isNetworkReachable else { return }
        guard !inFlightSiteIDs.contains(siteID) else { return }

        let all = (try? context.fetch(FetchDescriptor<PublishedBusinessSite>())) ?? []
        guard let site = all.first(where: { $0.id == siteID }) else { return }
        guard site.needsSync else { return }

        inFlightSiteIDs.insert(siteID)
        defer { inFlightSiteIDs.remove(siteID) }

        await publishPublicSite(site: site, context: context)
    }

    private func uploadAssetsIfNeeded(site: PublishedBusinessSite) async throws {
        if let localHeroPath = normalizedLocalPath(site.heroImageLocalPath),
           shouldUploadAsset(localPath: localHeroPath, remoteUrl: site.heroImageRemoteUrl) {
            let heroData = try preparedAssetData(localPath: localHeroPath)
            let heroURL = try await PortalBackend.shared.uploadPublicSiteAssetToBlob(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                kind: "hero",
                fileName: uploadFileName(prefix: "hero", localPath: localHeroPath),
                data: heroData
            )
            site.heroImageRemoteUrl = heroURL
        }

        if let localAboutPath = normalizedLocalPath(site.aboutImageLocalPath),
           shouldUploadAsset(localPath: localAboutPath, remoteUrl: site.aboutImageRemoteUrl) {
            let aboutData = try preparedAssetData(localPath: localAboutPath)
            let aboutURL = try await PortalBackend.shared.uploadPublicSiteAssetToBlob(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                kind: "asset",
                fileName: uploadFileName(prefix: "about", localPath: localAboutPath),
                data: aboutData
            )
            site.aboutImageRemoteUrl = aboutURL
        }

        var team = site.teamMembersV2
        if !team.isEmpty {
            let localPathMap = site.teamPhotoLocalPathById
            for index in team.indices {
                let memberID = team[index].id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !memberID.isEmpty else { continue }
                guard let localPath = normalizedLocalPath(localPathMap[memberID]) else { continue }

                if !shouldUploadAsset(localPath: localPath, remoteUrl: team[index].photoUrl) {
                    continue
                }

                let data = try preparedAssetData(localPath: localPath)
                let uploadedURL = try await PortalBackend.shared.uploadPublicSiteAssetToBlob(
                    businessId: site.businessID.uuidString,
                    handle: site.handle,
                    kind: "asset",
                    fileName: uploadFileName(prefix: "team-\(memberID)", localPath: localPath),
                    data: data
                )
                team[index].photoUrl = uploadedURL
            }
            site.teamMembersV2 = team
        }

        if !site.galleryLocalPaths.isEmpty {
            var resolvedGalleryURLs: [String] = []
            let existing = site.galleryRemoteUrls

            for (index, rawPath) in site.galleryLocalPaths.enumerated() {
                let localPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !localPath.isEmpty else { continue }

                let candidateAtIndex: String? = index < existing.count ? existing[index] : nil
                let matchingExisting = existing.first(where: { url in
                    urlLooksCurrent(localPath: localPath, remoteUrl: url)
                })

                let chosenExisting = candidateAtIndex ?? matchingExisting
                if !shouldUploadAsset(localPath: localPath, remoteUrl: chosenExisting) {
                    if let chosenExisting, !chosenExisting.isEmpty {
                        resolvedGalleryURLs.append(chosenExisting)
                    }
                    continue
                }

                let data = try preparedAssetData(localPath: localPath)
                let uploadedURL = try await PortalBackend.shared.uploadPublicSiteAssetToBlob(
                    businessId: site.businessID.uuidString,
                    handle: site.handle,
                    kind: "gallery",
                    fileName: uploadFileName(prefix: "gallery-\(index)", localPath: localPath),
                    data: data
                )
                resolvedGalleryURLs.append(uploadedURL)
            }

            site.galleryRemoteUrls = resolvedGalleryURLs
        }
    }

    private func normalizedLocalPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func shouldUploadAsset(localPath: String, remoteUrl: String?) -> Bool {
        let remote = remoteUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if remote.isEmpty { return true }
        return !urlLooksCurrent(localPath: localPath, remoteUrl: remote)
    }

    private func urlLooksCurrent(localPath: String, remoteUrl: String) -> Bool {
        let fileName = URL(fileURLWithPath: localPath).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return false }
        return remoteUrl.localizedCaseInsensitiveContains(fileName)
    }

    private func uploadFileName(prefix: String, localPath: String) -> String {
        let original = URL(fileURLWithPath: localPath).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if original.isEmpty {
            return "\(prefix)-\(UUID().uuidString).jpg"
        }
        return "\(prefix)-\(original)"
    }

    private func preparedAssetData(localPath: String) throws -> Data {
        let sourceURL = URL(fileURLWithPath: localPath)
        let rawData = try Data(contentsOf: sourceURL)

        if let image = UIImage(data: rawData) {
            if let compressed = compressedImageData(from: image), compressed.count <= maxUploadBytes {
                return compressed
            }
            if rawData.count <= maxUploadBytes {
                return rawData
            }
            throw BusinessSitePublishError.assetTooLarge
        }

        guard rawData.count <= maxUploadBytes else {
            throw BusinessSitePublishError.assetTooLarge
        }
        return rawData
    }

    private func compressedImageData(from image: UIImage) -> Data? {
        let resized = downscaled(image: image, maxDimension: maxPublicImageDimension)

        var quality = targetJPEGQuality
        var data = resized.jpegData(compressionQuality: quality)

        while let encoded = data, encoded.count > maxUploadBytes, quality > 0.42 {
            quality -= 0.08
            data = resized.jpegData(compressionQuality: quality)
        }

        if let encoded = data, encoded.count <= maxUploadBytes {
            return encoded
        }

        var shrinkScale: CGFloat = 0.9
        var working = resized
        while shrinkScale >= 0.6 {
            let nextMax = max(700, max(working.size.width, working.size.height) * shrinkScale)
            working = downscaled(image: working, maxDimension: nextMax)
            data = working.jpegData(compressionQuality: max(0.45, quality))
            if let encoded = data, encoded.count <= maxUploadBytes {
                return encoded
            }
            shrinkScale -= 0.1
        }

        return data
    }

    private func downscaled(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let currentMax = max(width, height)
        guard currentMax > maxDimension, currentMax > 0 else {
            return image
        }

        let scaleRatio = maxDimension / currentMax
        let targetSize = CGSize(width: floor(width * scaleRatio), height: floor(height * scaleRatio))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func persistTemporaryAsset(
        data: Data,
        businessID: UUID,
        prefix: String,
        fileExtension: String
    ) throws -> String {
        let fileName = "\(prefix)-\(businessID.uuidString).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url.path
    }
}

enum BusinessSitePublishError: LocalizedError {
    case invalidHandle
    case assetTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidHandle:
            return "Add a website handle before publishing. Use letters, numbers, and dashes only."
        case .assetTooLarge:
            return "One or more images are too large to publish."
        }
    }
}
