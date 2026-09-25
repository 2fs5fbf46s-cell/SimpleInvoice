//
//  InvoicePayment.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// One payment toward an invoice: a check the owner recorded, or an online
/// payment the portal reported. An invoice used to be simply paid or not, so
/// a $200 check against a $450 invoice had nowhere to go.
@Model
final class InvoicePayment {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    /// invoice.id.uuidString, for predicates (same idiom as InvoiceAttachment).
    var invoiceKey: String = ""
    var amountCents: Int = 0
    var paidAt: Date = Foundation.Date()
    /// "cash", "check", "card", "bank", "zelle", "venmo", "cashapp", "paypal",
    /// "other" for recorded payments; the provider ("stripe", "paypal", …)
    /// for ones the portal reported.
    var method: String = "other"
    var note: String = ""
    /// "manual" or "portal".
    var source: String = "manual"

    @Relationship var invoice: Invoice? = nil

    init() {}

    init(invoice: Invoice, amountCents: Int, paidAt: Date, method: String, note: String = "", source: String = "manual") {
        self.invoice = invoice
        self.invoiceKey = invoice.id.uuidString
        self.amountCents = amountCents
        self.paidAt = paidAt
        self.method = method
        self.note = note
        self.source = source
        self.createdAt = .now
    }

    static let methods: [(key: String, label: String)] = [
        ("cash", "Cash"),
        ("check", "Check"),
        ("card", "Card"),
        ("bank", "Bank transfer"),
        ("zelle", "Zelle"),
        ("venmo", "Venmo"),
        ("cashapp", "Cash App"),
        ("paypal", "PayPal"),
        ("other", "Other"),
    ]

    var methodLabel: String {
        switch method {
        case "stripe": return "Card (online)"
        default: return Self.methods.first { $0.key == method }?.label ?? method.capitalized
        }
    }
}
