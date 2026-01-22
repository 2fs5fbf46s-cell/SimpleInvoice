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

    static func appSupportBaseURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppFileStoreError.cannotAccessApplicationSupport
        }
        let base = appSupport.appendingPathComponent(baseFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    static func filesRootURL() throws -> URL {
        let root = try appSupportBaseURL().appendingPathComponent(filesFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    /// Copies a file into app storage under a stable folder using fileId.
    /// Returns (relativePath, byteCount)
    static func importFile(from sourceURL: URL, fileId: UUID, preferredFileName: String? = nil) throws -> (String, Int64) {
        let root = try filesRootURL()
        let container = root.appendingPathComponent(fileId.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: container.path) {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        }

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

    static func absoluteURL(forRelativePath rel: String) throws -> URL {
        return try appSupportBaseURL().appendingPathComponent(rel, isDirectory: false)
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

        if !FileManager.default.fileExists(atPath: container.path) {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        }

        let destURL = container.appendingPathComponent(preferredFileName, isDirectory: false)
        let finalURL = uniqueURLIfNeeded(destURL)

        try data.write(to: finalURL, options: .atomic)

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)

        let base = try appSupportBaseURL()
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
}
