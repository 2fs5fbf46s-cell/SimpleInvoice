//
//  WebsiteImageStore.swift
//  SmallBiz Workspace
//

import Foundation

/// Where the website's photos (hero, about, team, gallery) are kept on the
/// phone until they're published.
///
/// They used to be written to the temporary folder, which iOS empties when
/// it likes, so a photo picked today could be gone before the site was
/// published; and they were remembered by full path, which changes when an
/// app update moves the app's folder. Now they live in Application Support
/// and are found again by file name.
enum WebsiteImageStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WebsiteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves the image and returns the path to remember.
    static func write(_ data: Data, fileName: String) throws -> String {
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    /// The file for a remembered path: as stored, or by name in the images
    /// folder (the app's folder moved, or it was saved before this store).
    static func resolve(_ stored: String?) -> String? {
        guard let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty else { return nil }
        if FileManager.default.fileExists(atPath: stored) { return stored }
        let byName = directory.appendingPathComponent(URL(fileURLWithPath: stored).lastPathComponent).path
        return FileManager.default.fileExists(atPath: byName) ? byName : nil
    }
}
