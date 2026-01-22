//
//  AttachmentZipExporter.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/16/26.
//

import Foundation
import ZIPFoundation

enum AttachmentZipExporter {
    /// Zips a list of files by copying them into a temp folder, then zipping that folder.
    /// - Returns: URL to the created .zip file in temp directory.
    static func zipFiles(
        _ fileURLs: [URL],
        zipName: String
    ) throws -> URL {

        let fm = FileManager.default

        // Defensive: filter out missing files
        let existing = fileURLs.filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            throw ZipError.noFiles
        }

        // Create a staging folder in temp
        let tempRoot = fm.temporaryDirectory
        let stagingFolder = tempRoot.appendingPathComponent("SBW-Zip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)

        // Copy files into staging folder with collision-safe names
        for url in existing {
            let safeName = makeUniqueFileName(
                preferred: url.lastPathComponent,
                in: stagingFolder
            )
            let dest = stagingFolder.appendingPathComponent(safeName)

            do {
                try fm.copyItem(at: url, to: dest)
            } catch {
                // If a single file fails, continue with the rest
                // (You can choose to throw instead if you want strict behavior)
                continue
            }
        }

        // Create the zip (zip the staging folder)
        let sanitizedZipName = sanitize(zipName)
        let zipURL = tempRoot.appendingPathComponent("\(sanitizedZipName).zip")

        // Remove old zip if it exists
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        // iOS 16+ Foundation convenience API
        try fm.zipItem(at: stagingFolder, to: zipURL, shouldKeepParent: false)

        // Cleanup staging folder
        try? fm.removeItem(at: stagingFolder)

        return zipURL
    }

    // MARK: - Helpers

    private static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Attachments" }

        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = trimmed
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
        return cleaned
    }

    private static func makeUniqueFileName(preferred: String, in folder: URL) -> String {
        let fm = FileManager.default
        let base = preferred.isEmpty ? "File" : preferred

        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension

        var candidate = base
        var i = 2

        while fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            if ext.isEmpty {
                candidate = "\(stem) (\(i))"
            } else {
                candidate = "\(stem) (\(i)).\(ext)"
            }
            i += 1
        }
        return candidate
    }

    enum ZipError: LocalizedError {
        case noFiles

        var errorDescription: String? {
            switch self {
            case .noFiles: return "No attachment files were found to export."
            }
        }
    }
}
