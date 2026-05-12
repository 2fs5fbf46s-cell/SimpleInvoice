import Foundation
import SwiftData

struct CatalogItemAutoSaveResult {
    let item: CatalogItem
    let created: Bool
}

@MainActor
enum CatalogItemAutoSaveService {
    static func saveLineItem(
        _ item: LineItem,
        businessID: UUID?,
        context: ModelContext,
        sessionCatalogItem: CatalogItem? = nil
    ) throws -> CatalogItemAutoSaveResult? {
        let parsed = parseLineItemDescription(item.itemDescription)
        return try save(
            name: parsed.name,
            details: parsed.details,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            businessID: businessID,
            context: context,
            sessionCatalogItem: sessionCatalogItem
        )
    }

    static func save(
        name rawName: String,
        details rawDetails: String,
        unitPrice: Double,
        quantity: Double,
        businessID: UUID?,
        context: ModelContext,
        sessionCatalogItem: CatalogItem? = nil
    ) throws -> CatalogItemAutoSaveResult? {
        guard let businessID else { return nil }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = rawDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, unitPrice.isFinite, unitPrice >= 0 else { return nil }

        let defaultQuantity = normalizedDefaultQuantity(quantity)

        if let sessionCatalogItem, sessionCatalogItem.businessID == businessID {
            apply(
                name: name,
                details: details,
                unitPrice: unitPrice,
                defaultQuantity: defaultQuantity,
                to: sessionCatalogItem,
                force: true
            )
            try context.save()
            return CatalogItemAutoSaveResult(item: sessionCatalogItem, created: false)
        }

        let descriptor = FetchDescriptor<CatalogItem>(
            predicate: #Predicate<CatalogItem> { item in
                item.businessID == businessID
            },
            sortBy: [SortDescriptor(\CatalogItem.name)]
        )
        let existingItems = try context.fetch(descriptor)
        let normalizedName = normalizedCatalogName(name)
        let sameNameItems = existingItems.filter {
            normalizedCatalogName($0.name) == normalizedName
        }

        if let existing = sameNameItems.first(where: { pricesMatch($0.unitPrice, unitPrice) }) ?? sameNameItems.first {
            apply(
                name: name,
                details: details,
                unitPrice: unitPrice,
                defaultQuantity: defaultQuantity,
                to: existing,
                force: false
            )
            try context.save()
            return CatalogItemAutoSaveResult(item: existing, created: false)
        }

        let created = CatalogItem(
            name: name,
            details: details,
            unitPrice: unitPrice,
            defaultQuantity: defaultQuantity,
            category: "General"
        )
        created.businessID = businessID
        context.insert(created)
        try context.save()
        return CatalogItemAutoSaveResult(item: created, created: true)
    }

    static func parseLineItemDescription(_ value: String) -> (name: String, details: String) {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        let firstLine = (lines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingLines = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !remainingLines.isEmpty {
            return (firstLine, remainingLines)
        }

        for separator in [" -- ", " - ", " \u{2013} ", " \u{2014} "] {
            if let range = firstLine.range(of: separator) {
                let name = String(firstLine[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let details = String(firstLine[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (name, details)
            }
        }

        return (firstLine, "")
    }

    static func combineLineItemDescription(name: String, details: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return trimmedDetails }
        if trimmedDetails.isEmpty { return trimmedName }
        return "\(trimmedName)\n\(trimmedDetails)"
    }

    static func normalizedCatalogName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func apply(
        name: String,
        details: String,
        unitPrice: Double,
        defaultQuantity: Double,
        to item: CatalogItem,
        force: Bool
    ) {
        if force {
            item.name = name
            item.details = details
            item.unitPrice = unitPrice
            item.defaultQuantity = defaultQuantity
            item.category = normalizedCategory(item.category)
            return
        }

        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.name = name
        }
        if item.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !details.isEmpty {
            item.details = details
        }
        if item.unitPrice == 0, unitPrice != 0 {
            item.unitPrice = unitPrice
        }
        if item.defaultQuantity <= 0 {
            item.defaultQuantity = defaultQuantity
        }
        item.category = normalizedCategory(item.category)
    }

    private static func normalizedCategory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General" : trimmed
    }

    private static func normalizedDefaultQuantity(_ quantity: Double) -> Double {
        guard quantity.isFinite, quantity > 0 else { return 1 }
        return quantity
    }

    private static func pricesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.005
    }
}
