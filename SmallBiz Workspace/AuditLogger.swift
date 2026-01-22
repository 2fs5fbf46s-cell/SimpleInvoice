import Foundation
import SwiftData
import UIKit

@MainActor
final class AuditLogger {
    static let shared = AuditLogger()
    private init() {}

    private var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    func log(
        modelContext: ModelContext,
        businessID: UUID,
        entityType: String,
        entityID: UUID,
        action: AuditAction,
        summary: String,
        diff: [String: Any]? = nil
    ) {
        let diffJSON: String? = {
            guard let diff else { return nil }
            if let data = try? JSONSerialization.data(withJSONObject: diff, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return nil
        }()

        let event = AuditEvent(
            businessID: businessID,
            entityType: entityType,
            entityID: entityID,
            action: action,
            summary: summary,
            diffJSON: diffJSON,
            deviceID: deviceID
        )
        modelContext.insert(event)
        // no forced save here; caller controls save timing
    }
}
