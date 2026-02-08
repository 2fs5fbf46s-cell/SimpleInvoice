import Foundation
import SwiftData
import Network

@MainActor
final class BusinessSitePublishService {
    static let shared = BusinessSitePublishService()

    private var monitor: NWPathMonitor?
    private var isNetworkReachable = true
    private var inFlightSiteIDs: Set<UUID> = []

    private init() {}

    func startMonitoring(context: ModelContext) {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "BusinessSitePublishService.Network")
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let becameReachable = !self.isNetworkReachable && path.status == .satisfied
                self.isNetworkReachable = path.status == .satisfied

                if becameReachable {
                    await self.syncQueuedSites(context: context)
                }
            }
        }

        monitor.start(queue: queue)
        self.monitor = monitor
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
        draft.updatedAt = .now
        if draft.publishStatus == PublishStatus.published.rawValue {
            draft.publishStatus = PublishStatus.draft.rawValue
        }
        try? context.save()
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

        site.publishStatus = PublishStatus.publishing.rawValue
        site.lastPublishError = nil
        try? context.save()

        do {
            try await uploadAssetsIfNeeded(site: site)

            let payload = PublicSiteUpsertPayload(
                appName: site.appName,
                heroUrl: site.heroImageRemoteUrl,
                services: site.services,
                aboutUs: site.aboutUs,
                team: site.teamMembers,
                galleryUrls: site.galleryRemoteUrls,
                updatedAtMs: Int(site.updatedAt.timeIntervalSince1970 * 1000)
            )

            _ = try await PortalBackend.shared.upsertPublicSite(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                payload: payload
            )

            site.publishStatus = PublishStatus.published.rawValue
            site.lastPublishedAt = .now
            site.needsSync = false
            site.lastPublishError = nil
            try? context.save()
        } catch {
            site.publishStatus = PublishStatus.error.rawValue
            site.lastPublishError = error.localizedDescription
            site.needsSync = true
            try? context.save()
        }
    }

    private func uploadAssetsIfNeeded(site: PublishedBusinessSite) async throws {
        if let localHeroPath = site.heroImageLocalPath,
           !localHeroPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           site.heroImageRemoteUrl == nil,
           let heroData = try? Data(contentsOf: URL(fileURLWithPath: localHeroPath)) {
            let heroURL = try await PortalBackend.shared.uploadSiteAssetToBlob(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                kind: "hero",
                fileName: URL(fileURLWithPath: localHeroPath).lastPathComponent,
                data: heroData
            )
            site.heroImageRemoteUrl = heroURL
        }

        if let localAboutPath = site.aboutImageLocalPath,
           !localAboutPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           site.aboutImageRemoteUrl == nil,
           let aboutData = try? Data(contentsOf: URL(fileURLWithPath: localAboutPath)) {
            let aboutURL = try await PortalBackend.shared.uploadSiteAssetToBlob(
                businessId: site.businessID.uuidString,
                handle: site.handle,
                kind: "gallery",
                fileName: URL(fileURLWithPath: localAboutPath).lastPathComponent,
                data: aboutData
            )
            site.aboutImageRemoteUrl = aboutURL
            if !site.galleryRemoteUrls.contains(aboutURL) {
                site.galleryRemoteUrls.insert(aboutURL, at: 0)
            }
        }

        guard !site.galleryLocalPaths.isEmpty else { return }

        var remoteURLs = site.galleryRemoteUrls
        let startIndex = min(remoteURLs.count, site.galleryLocalPaths.count)

        if startIndex < site.galleryLocalPaths.count {
            for index in startIndex..<site.galleryLocalPaths.count {
                let localPath = site.galleryLocalPaths[index]
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) else { continue }

                let uploadedURL = try await PortalBackend.shared.uploadSiteAssetToBlob(
                    businessId: site.businessID.uuidString,
                    handle: site.handle,
                    kind: "gallery",
                    fileName: URL(fileURLWithPath: localPath).lastPathComponent,
                    data: data
                )
                remoteURLs.append(uploadedURL)
            }
        }

        site.galleryRemoteUrls = remoteURLs
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

    var errorDescription: String? {
        switch self {
        case .invalidHandle:
            return "Add a website handle before publishing. Use letters, numbers, and dashes only."
        }
    }
}
