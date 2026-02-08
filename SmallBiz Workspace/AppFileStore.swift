//
//  AppFileStore.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation

enum AppFileStoreError: Error {
    case cannotAccessApplicationSupport
    case cannotCreateDirectory
    case copyFailed
}

struct AppFileStore {
    static let baseFolderName = "SmallBizWorkspace"
    static let filesFolderName = "files"
    private static let baseOverrideEnv = "SBW_FILESTORE_BASE_URL"

    static func appSupportBaseURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment[baseOverrideEnv], !override.isEmpty {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: true)
            try ensureDirectory(at: overrideURL)
            return overrideURL
        }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppFileStoreError.cannotAccessApplicationSupport
        }
        try ensureDirectory(at: appSupport)
        let base = appSupport.appendingPathComponent(baseFolderName, isDirectory: true)
        try ensureDirectory(at: base)
        return base
    }

    static func filesRootURL() throws -> URL {
        let root = try appSupportBaseURL().appendingPathComponent(filesFolderName, isDirectory: true)
        try ensureDirectory(at: root)
        return root
    }

    /// Copies a file into app storage under a stable folder using fileId.
    /// Returns (relativePath, byteCount)
    static func importFile(from sourceURL: URL, fileId: UUID, preferredFileName: String? = nil) throws -> (String, Int64) {
        let root = try filesRootURL()
        let container = root.appendingPathComponent(fileId.uuidString, isDirectory: true)
        try ensureDirectory(at: container)

        let name = (preferredFileName?.isEmpty == false ? preferredFileName! : sourceURL.lastPathComponent)
        let destURL = container.appendingPathComponent(name, isDirectory: false)

        // If name collision, add "-1", "-2", etc.
        let finalURL = uniqueURLIfNeeded(destURL)

        // Copy
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: finalURL)
        } catch {
            throw AppFileStoreError.copyFailed
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        // Make relative path from Application Support base
        let base = try appSupportBaseURL()
        let rel = finalURL.path.replacingOccurrences(of: base.path + "/", with: "")
        return (rel, size)
    }

    static func importFile(
        from sourceURL: URL,
        toRelativeFolderPath folderRelativePath: String,
        preferredFileName: String? = nil
    ) throws -> (String, Int64) {
        let base = try appSupportBaseURL()
        let folderPath = folderRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let folderURL = base.appendingPathComponent(folderPath, isDirectory: true)
        try ensureDirectory(at: folderURL)

        let name = (preferredFileName?.isEmpty == false ? preferredFileName! : sourceURL.lastPathComponent)
        let destURL = folderURL.appendingPathComponent(name, isDirectory: false)
        let finalURL = uniqueURLIfNeeded(destURL)

        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: finalURL)
        } catch {
            throw AppFileStoreError.copyFailed
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let rel = finalURL.path.replacingOccurrences(of: base.path + "/", with: "")
        return (rel, size)
    }

    static func absoluteURL(forRelativePath rel: String) throws -> URL {
        return try appSupportBaseURL().appendingPathComponent(rel, isDirectory: false)
    }

    /// Writes data into a stable relative path under Application Support.
    /// Returns byteCount.
    static func writeData(_ data: Data, toRelativePath rel: String) throws -> Int64 {
        let base = try appSupportBaseURL()
        let destURL = base.appendingPathComponent(rel, isDirectory: false)
        let parent = destURL.deletingLastPathComponent()
        try ensureDirectory(at: parent)

        try data.write(to: destURL, options: .atomic)

        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
    }

    static func deleteFile(for item: FileItem) throws {
        let url = try absoluteURL(forRelativePath: item.relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // Also remove the fileId folder if empty
        let parent = url.deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path), contents.isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
    }
    static func importData(_ data: Data, fileId: UUID, preferredFileName: String) throws -> (String, Int64) {
        let root = try filesRootURL()
        let container = root.appendingPathComponent(fileId.uuidString, isDirectory: true)

        try ensureDirectory(at: container)

        let destURL = container.appendingPathComponent(preferredFileName, isDirectory: false)
        let finalURL = uniqueURLIfNeeded(destURL)

        try data.write(to: finalURL, options: .atomic)

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)

        let base = try appSupportBaseURL()
        let rel = finalURL.path.replacingOccurrences(of: base.path + "/", with: "")
        return (rel, size)
    }

    static func importData(
        _ data: Data,
        toRelativeFolderPath folderRelativePath: String,
        preferredFileName: String
    ) throws -> (String, Int64) {
        let base = try appSupportBaseURL()
        let folderPath = folderRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let folderURL = base.appendingPathComponent(folderPath, isDirectory: true)
        try ensureDirectory(at: folderURL)

        let destURL = folderURL.appendingPathComponent(preferredFileName, isDirectory: false)
        let finalURL = uniqueURLIfNeeded(destURL)
        try data.write(to: finalURL, options: .atomic)

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
        let rel = finalURL.path.replacingOccurrences(of: base.path + "/", with: "")
        return (rel, size)
    }


    private static func uniqueURLIfNeeded(_ url: URL) -> URL {
        var candidate = url
        let fm = FileManager.default
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()

        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            i += 1
        }
        return candidate
    }

    private static func ensureDirectory(at url: URL) throws {
        if url.path.isEmpty || url.path == "/" {
            return
        }

        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if parent.path != url.path && !parent.path.isEmpty && parent.path != "/" {
            try ensureDirectory(at: parent)
        }

        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists {
            if !isDirectory.boolValue {
                try fm.removeItem(at: url)
            } else {
                return
            }
        }

        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            // A concurrent caller may have created the folder between the existence check and create call.
            var postCreateIsDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &postCreateIsDirectory), postCreateIsDirectory.boolValue {
                return
            }
            throw error
        }
    }
}
