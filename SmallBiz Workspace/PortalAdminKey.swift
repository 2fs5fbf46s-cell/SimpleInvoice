//
//  PortalAdminKey.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/23/26.
//

import Foundation

enum PortalAdminKey {
    static var value: String {
        guard
            let url = Bundle.main.url(forResource: "PortalSecrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let raw = dict["PORTAL_ADMIN_KEY"]
        else { return "" }

        // Handle String or other plist scalar types gracefully
        if let s = raw as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

