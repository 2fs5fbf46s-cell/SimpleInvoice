//
//  FileKind.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import UniformTypeIdentifiers

/// Simple classification for files.
/// CloudKit-safe because it stores as a raw string.
enum FileKind: String, Codable, CaseIterable {
    case pdf
    case image
    case text
    case audio
    case video
    case archive
    case other

    static func from(fileExtension ext: String) -> FileKind {
        let ext = ext.lowercased()

        if ext == "pdf" { return .pdf }
        if ["jpg","jpeg","png","heic","gif","tiff","bmp","webp"].contains(ext) { return .image }
        if ["txt","rtf","md","csv","json","xml"].contains(ext) { return .text }
        if ["mp3","wav","aiff","m4a","aac"].contains(ext) { return .audio }
        if ["mp4","mov","m4v"].contains(ext) { return .video }
        if ["zip","rar","7z","tar","gz"].contains(ext) { return .archive }

        return .other
    }

    static func from(uti: String) -> FileKind {
        guard let t = UTType(uti) else { return .other }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .text) { return .text }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .movie) { return .video }
        return .other
    }
}
