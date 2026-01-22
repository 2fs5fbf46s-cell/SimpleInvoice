//
//  ContractTemplate.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

@Model
final class ContractTemplate {
    // ✅ CloudKit-safe: defaults must be on the properties
    var name: String = ""
    var category: String = "General"
    var body: String = ""

    var isBuiltIn: Bool = false
    var version: Int = 1

    init(
        name: String = "",
        category: String = "General",
        body: String = "",
        isBuiltIn: Bool = false,
        version: Int = 1
    ) {
        self.name = name
        self.category = category
        self.body = body
        self.isBuiltIn = isBuiltIn
        self.version = version
    }
}
