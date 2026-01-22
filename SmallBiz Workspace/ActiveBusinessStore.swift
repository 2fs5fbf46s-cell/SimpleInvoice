//
//  ActiveBusinessStore.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class ActiveBusinessStore: ObservableObject {
    @AppStorage("activeBusinessID") private var activeBusinessIDString: String = ""

    @Published var activeBusinessID: UUID? = nil

    func loadOrCreateDefaultBusiness(modelContext: ModelContext) throws {
        let businesses = try modelContext.fetch(FetchDescriptor<Business>())

        // If no businesses exist, create one
        if businesses.isEmpty {
            let created = Business(name: "Default Business", isActive: true)
            modelContext.insert(created)
            try modelContext.save()
            setActiveBusiness(created.id)
            return
        }

        // If we have an active business saved, use it
        if let saved = UUID(uuidString: activeBusinessIDString),
           businesses.contains(where: { $0.id == saved }) {
            activeBusinessID = saved
            return
        }

        // Otherwise pick the first active business, else first business
        let first = businesses.first(where: { $0.isActive }) ?? businesses[0]
        setActiveBusiness(first.id)
    }

    func setActiveBusiness(_ id: UUID) {
        activeBusinessID = id
        activeBusinessIDString = id.uuidString
    }
}
