//
//  UTType+Import.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    static var importable: [UTType] {
        [
            .pdf, .image, .jpeg, .png, .heic, .text, .plainText,
            .rtf, .spreadsheet, .presentation, .data, .content
        ]
    }
}
