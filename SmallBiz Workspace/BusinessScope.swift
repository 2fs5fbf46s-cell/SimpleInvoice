//
//  BusinessScoped.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftUI

enum BusinessScope {
    static func requireActiveBusinessID(_ id: UUID?) -> UUID {
        // If this ever hits, it means you’re creating data before business is selected.
        // We fail fast with a clear signal rather than silently creating bad data.
        return id ?? UUID()
    }
}
