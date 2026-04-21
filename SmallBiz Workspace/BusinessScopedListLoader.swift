//
//  BusinessScopedListLoader.swift
//  SmallBiz Workspace
//

import Foundation

struct BusinessScopedListLoader {
    private(set) var generation = UUID()

    mutating func nextGeneration() -> UUID {
        let next = UUID()
        generation = next
        return next
    }

    func isCurrent(_ generation: UUID) -> Bool {
        self.generation == generation
    }
}
