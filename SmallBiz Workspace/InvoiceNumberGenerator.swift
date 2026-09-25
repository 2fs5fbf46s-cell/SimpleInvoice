//
//  InvoiceNumberGenerator.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/11/26.
//

import Foundation

enum InvoiceNumberGenerator {

    static func generateNextNumber(profile: BusinessProfile, date: Date = .now) -> String {
        consumeNextNumber(profile: profile, date: date)
    }

    static func peekNextNumber(profile: BusinessProfile, date: Date = .now) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: date)
        let nextValue = profile.lastInvoiceYear == currentYear ? profile.nextInvoiceNumber : 1
        return formattedNumber(profile: profile, year: currentYear, number: nextValue)
    }

    static func consumeNextNumber(profile: BusinessProfile, date: Date = .now) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: date)

        // Yearly reset
        if profile.lastInvoiceYear != currentYear {
            profile.lastInvoiceYear = currentYear
            profile.nextInvoiceNumber = 1
        }

        let invoiceNumber = formattedNumber(profile: profile, year: currentYear, number: profile.nextInvoiceNumber)

        // Increment for next invoice
        profile.nextInvoiceNumber += 1

        return invoiceNumber
    }

    /// Gives back a number nothing ended up using (a new invoice left
    /// untouched), but only if it's the last one handed out, so numbers
    /// already on other invoices never repeat.
    static func release(_ number: String, profile: BusinessProfile, date: Date = .now) {
        let year = Calendar.current.component(.year, from: date)
        guard profile.lastInvoiceYear == year,
              profile.nextInvoiceNumber > 1,
              formattedNumber(profile: profile, year: year, number: profile.nextInvoiceNumber - 1) == number
        else { return }
        profile.nextInvoiceNumber -= 1
    }

    private static func formattedNumber(profile: BusinessProfile, year: Int, number: Int) -> String {
        let formatted = String(format: "%03d", number)
        let trimmed = profile.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.isEmpty ? "SI" : trimmed.uppercased()
        return "\(prefix)-\(year)-\(formatted)"
    }
}
