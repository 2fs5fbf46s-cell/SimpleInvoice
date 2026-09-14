//
//  ExpenseAttachment.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

@Model
final class ExpenseAttachment {
    // Identity (CloudKit-safe: default values)
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    // Stable keys (Strings are easiest for SwiftData predicates + CloudKit)
    var expenseKey: String = ""   // expense.id.uuidString
    var fileKey: String = ""      // fileItem.id.uuidString

    // Optional relationships (CloudKit requires relationships optional)
    @Relationship var expense: Expense? = nil
    @Relationship var file: FileItem? = nil

    init() {}

    init(expense: Expense, file: FileItem) {
        self.expense = expense
        self.file = file
        self.expenseKey = expense.id.uuidString
        self.fileKey = file.id.uuidString
        self.createdAt = .now
    }
}
