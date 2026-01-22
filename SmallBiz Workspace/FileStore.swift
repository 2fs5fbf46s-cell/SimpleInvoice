import Foundation
import UniformTypeIdentifiers

enum FileStoreError: Error {
    case cannotAccessRoot
    case invalidRelativePath
}

final class FileStore {
    static let shared = FileStore()
    private init() {}

    // Root folder name inside iCloud Documents or local Documents
    private let rootFolderName = "SmallBizWorkspace"

    // Returns iCloud Documents container if available, else local documents
    func rootURL() throws -> URL {
        // iCloud Documents container (Documents scope)
        if let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let docs = ubiq.appendingPathComponent("Documents", isDirectory: true)
            let root = docs.appendingPathComponent(rootFolderName, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }

        // Local fallback
        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let localDocs else { throw FileStoreError.cannotAccessRoot }
        let root = localDocs.appendingPathComponent(rootFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func folderURL(relativePath: String) throws -> URL {
        guard !relativePath.contains("..") else { throw FileStoreError.invalidRelativePath }
        let root = try rootURL()
        return root.appendingPathComponent(relativePath, isDirectory: true)
    }

    func fileURL(relativePath: String) throws -> URL {
        guard !relativePath.contains("..") else { throw FileStoreError.invalidRelativePath }
        let root = try rootURL()
        return root.appendingPathComponent(relativePath, isDirectory: false)
    }

    func createFolder(relativePath: String) throws {
        let url = try folderURL(relativePath: relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func deleteItem(relativePath: String) throws {
        let url = try fileURL(relativePath: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func importFile(from sourceURL: URL, toRelativeFolder folderRelativePath: String, preferredFileName: String? = nil) throws -> (relativePath: String, size: Int64) {
        let folderURL = try folderURL(relativePath: folderRelativePath)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileName = preferredFileName ?? sourceURL.lastPathComponent
        let destURL = folderURL.appendingPathComponent(fileName, isDirectory: false)

        // Ensure unique name
        let finalURL = uniqueURL(destURL)

        // Copy
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: finalURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        // Compute relative path under root
        let root = try rootURL()
        let rel = finalURL.path.replacingOccurrences(of: root.path + "/", with: "")
        return (rel, size)
    }

    func detectKind(for url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["jpg","jpeg","png","heic","webp"].contains(ext) { return .image }
        if ["mov","mp4","m4v"].contains(ext) { return .video }
        if ["wav","mp3","m4a","aac"].contains(ext) { return .audio }
        if ["txt","md","rtf","json","csv"].contains(ext) { return .text }
        if ["zip","rar","7z"].contains(ext) { return .archive }
        return .other
    }

    private func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let parent = url.deletingLastPathComponent()
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = parent.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }
}
