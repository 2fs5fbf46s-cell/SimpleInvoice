#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Sends every model's record type and field to the CloudKit Development
/// environment, so Production can be deployed from it.
///
/// Development only learns a field when a record carrying it is saved, so a
/// new field nobody has touched yet (a new setting, a payment field) was
/// missing from Development and would be left out of a Production deploy.
/// This is Apple's documented `initializeCloudKitSchema` step for SwiftData:
/// it has to run on the store before the app's own container opens it, so
/// Developer Tools arms it and it runs at the next launch.
enum CloudKitSchemaUploader {
    static let containerID = "iCloud.com.javonfreeman.smallbizworkspace"

    private static let requestKey = "debug.cloudkit.uploadSchemaOnNextLaunch"
    private static let resultKey = "debug.cloudkit.lastSchemaUpload"

    static func requestUploadOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: requestKey)
    }

    static var isRequested: Bool { UserDefaults.standard.bool(forKey: requestKey) }

    /// "Sent Oct 27, 2:14 AM" or "Failed Oct 27, 2:14 AM: …", nil if never run.
    static var lastResult: String? { UserDefaults.standard.string(forKey: resultKey) }

    /// Called from `AppModelContainerFactory.makeContainer` before the
    /// SwiftData container exists. Does nothing unless armed.
    static func uploadIfRequested(storeURL: URL) {
        guard isRequested else { return }
        UserDefaults.standard.set(false, forKey: requestKey)
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        do {
            try upload(storeURL: storeURL)
            UserDefaults.standard.set("Sent \(when)", forKey: resultKey)
            SBWLog.data.note("✅ CloudKit Development schema sent")
        } catch {
            UserDefaults.standard.set("Failed \(when): \(reason(for: error))", forKey: resultKey)
            SBWLog.data.problem("❌ CloudKit schema upload failed: \(error)")
        }
    }

    /// Core Data's own message is just "A Core Data error occurred"; the
    /// useful part ("…without an iCloud account") is in the failure reason.
    private static func reason(for error: Error) -> String {
        let ns = error as NSError
        if let reason = ns.localizedFailureReason { return reason }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.localizedFailureReason ?? underlying.localizedDescription
        }
        return ns.localizedDescription
    }

    private static func upload(storeURL: URL) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppModelContainerFactory.models) else {
            throw NSError(domain: "CloudKitSchemaUploader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't build the data model."
            ])
        }
        try autoreleasepool {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(name: "SmallBizWorkspace", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema()

            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
    }
}
#endif
