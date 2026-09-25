//
//  BusinessBrandSync.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData
import UIKit
import CryptoKit

/// Sends the business's name, brand color and logo to the server, which
/// shows them on the portal, booking page, website and emails.
///
/// Marked dirty on any change and pushed right away; a push that doesn't get
/// through stays dirty and goes again on the next background refresh. The
/// logo only uploads when it changed (compared by hash).
@MainActor
enum BusinessBrandSync {
    private static func dirtyKey(_ id: UUID) -> String { "sbw.brand.dirty.\(id.uuidString)" }
    private static func logoHashKey(_ id: UUID) -> String { "sbw.brand.logoHash.\(id.uuidString)" }

    static func markChanged(_ profile: BusinessProfile, context: ModelContext) {
        // The ID now: the profile may be gone by the time the task runs.
        let businessID = profile.businessID
        UserDefaults.standard.set(true, forKey: dirtyKey(businessID))
        Task { await push(businessID: businessID, context: context) }
    }

    /// Pushes if there's an unsent change for this business.
    static func pushIfNeeded(businessID: UUID?, context: ModelContext) async {
        guard let businessID else { return }
        // Never pushed (a business from before brands synced) counts as changed.
        let neverSynced = UserDefaults.standard.object(forKey: dirtyKey(businessID)) == nil
        guard neverSynced || UserDefaults.standard.bool(forKey: dirtyKey(businessID)) else { return }
        await push(businessID: businessID, context: context)
    }

    private static func push(businessID: UUID, context: ModelContext) async {
        // The server takes the active business's sign-in.
        guard UserDefaults.standard.string(forKey: "activeBusinessID") == businessID.uuidString else { return }
        guard let profile = try? context.fetch(FetchDescriptor<BusinessProfile>(
            predicate: #Predicate { $0.businessID == businessID }
        )).first else { return }

        let png = profile.logoData.flatMap(logoPNG)
        let hash = png.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let lastHash = UserDefaults.standard.string(forKey: logoHashKey(businessID))
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await PortalBackend.shared.upsertBusinessBrand(
                name: name.isEmpty ? nil : name,
                colorHex: BrandColor.resolved(profile.brandColorHex),
                logoPNG: hash != lastHash ? png : nil,
                clearLogo: png == nil && lastHash != nil
            )
            UserDefaults.standard.set(hash, forKey: logoHashKey(businessID))
            UserDefaults.standard.set(false, forKey: dirtyKey(businessID))
        } catch {
            SBWLog.portal.problem("Brand sync failed: \(error.localizedDescription)")
        }
    }

    /// At most 512px on the long side, as PNG: headers show it small.
    private static func logoPNG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 512 / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
