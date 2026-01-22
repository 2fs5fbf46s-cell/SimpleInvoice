//
//  InvoiceTemplate.swift
//  SimpleInvoice
//

import Foundation

struct InvoiceTemplateLineItem: Identifiable, Hashable {
    let id: UUID
    let description: String
    let quantity: Double
    let unitPrice: Double

    init(
        id: UUID = UUID(),
        description: String,
        quantity: Double,
        unitPrice: Double
    ) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

struct InvoiceTemplate: Identifiable, Hashable {
    let id: UUID
    let title: String
    let description: String

    let defaultLineItems: [InvoiceTemplateLineItem]
    let defaultPaymentTerms: String
    let defaultNotes: String
    let defaultTaxRate: Double
    let defaultDiscount: Double

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        defaultLineItems: [InvoiceTemplateLineItem],
        defaultPaymentTerms: String,
        defaultNotes: String,
        defaultTaxRate: Double,
        defaultDiscount: Double
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.defaultLineItems = defaultLineItems
        self.defaultPaymentTerms = defaultPaymentTerms
        self.defaultNotes = defaultNotes
        self.defaultTaxRate = defaultTaxRate
        self.defaultDiscount = defaultDiscount
    }
}
