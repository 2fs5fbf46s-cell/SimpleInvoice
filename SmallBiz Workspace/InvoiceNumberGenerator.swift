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

    private static func formattedNumber(profile: BusinessProfile, year: Int, number: Int) -> String {
        let formatted = String(format: "%03d", number)
        let trimmed = profile.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.isEmpty ? "SI" : trimmed.uppercased()
        return "\(prefix)-\(year)-\(formatted)"
    }
}
