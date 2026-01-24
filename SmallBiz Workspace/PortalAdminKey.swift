//
//  PortalAdminKey.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/23/26.
//

import Foundation

enum PortalAdminKey {
    static var value: String {
        Bundle.main.object(forInfoDictionaryKey: "PORTAL_ADMIN_KEY") as? String ?? ""
    }
}
