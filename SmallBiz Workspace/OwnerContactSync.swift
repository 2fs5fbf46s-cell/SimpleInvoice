//
//  OwnerContactSync.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Sends the business profile's email to the server, which uses it for
/// SmallBiz Workspace announcements such as the Tap to Pay on iPhone launch
/// email (Apple's requirement 6.1). Every one has an unsubscribe link.
///
/// Sends only when the email or name differs from what last got through, so
/// calling it on every launch and profile save costs nothing.
@MainActor
enum OwnerContactSync {
    private static func sentKey(_ id: UUID) -> String { "sbw.ownerContact.sent.\(id.uuidString)" }

    static func pushIfNeeded(businessID: UUID?, context: ModelContext) async {
        guard let businessID else { return }
        // The server takes the active business's sign-in.
        guard UserDefaults.standard.string(forKey: "activeBusinessID") == businessID.uuidString else { return }
        guard let profile = try? context.fetch(FetchDescriptor<BusinessProfile>(
            predicate: #Predicate { $0.businessID == businessID }
        )).first else { return }

        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = "\(email.lowercased())\n\(name)"
        guard UserDefaults.standard.string(forKey: sentKey(businessID)) != fingerprint else { return }

        do {
            try await PortalBackend.shared.saveOwnerContact(email: email, name: name)
            UserDefaults.standard.set(fingerprint, forKey: sentKey(businessID))
        } catch {
            SBWLog.portal.problem("Owner contact sync failed: \(error.localizedDescription)")
        }
    }
}
