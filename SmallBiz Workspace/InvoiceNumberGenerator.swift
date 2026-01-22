//
//  InvoiceNumberGenerator.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/11/26.
//

import Foundation

enum InvoiceNumberGenerator {

    static func generateNextNumber(profile: BusinessProfile, date: Date = .now) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: date)

        // Yearly reset
        if profile.lastInvoiceYear != currentYear {
            profile.lastInvoiceYear = currentYear
            profile.nextInvoiceNumber = 1
        }

        // Format: PREFIX-YYYY-###
        let formattedNumber = String(format: "%03d", profile.nextInvoiceNumber)

        let trimmed = profile.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.isEmpty ? "SI" : trimmed.uppercased()

        let invoiceNumber = "\(prefix)-\(currentYear)-\(formattedNumber)"

        // Increment for next invoice
        profile.nextInvoiceNumber += 1

        return invoiceNumber
    }
}
