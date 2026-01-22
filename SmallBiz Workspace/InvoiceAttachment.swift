//
//  InvoiceAttachment.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/15/26.
//

import Foundation
import SwiftData

@Model
final class InvoiceAttachment {
    // Identity (CloudKit-safe: default values)
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    // Stable keys (Strings are easiest for SwiftData predicates + CloudKit)
    var invoiceKey: String = ""   // invoice.id.uuidString
    var fileKey: String = ""      // fileItem.id.uuidString

    // Optional relationships (CloudKit requires relationships optional)
    @Relationship var invoice: Invoice? = nil
    @Relationship var file: FileItem? = nil

    init() {}

    init(invoice: Invoice, file: FileItem) {
        self.invoice = invoice
        self.file = file
        self.invoiceKey = invoice.id.uuidString
        self.fileKey = file.id.uuidString
        self.createdAt = .now
    }
}
