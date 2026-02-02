//
//  SBWTheme.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 2/1/26.
//

import Foundation
import SwiftUI

enum SBWTheme {
    // MARK: - Brand Colors (Option A)
    static let brandBlue  = Color(red: 0.12, green: 0.44, blue: 0.85)  // ~ #1E6FD9
    static let brandGreen = Color(red: 0.20, green: 0.78, blue: 0.35)  // ~ #34C759

    static let brandGradient = LinearGradient(
        colors: [brandBlue, brandGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Subtle tints for chips/backgrounds
    static let blueTint  = brandBlue.opacity(0.14)
    static let greenTint = brandGreen.opacity(0.14)

    // MARK: - Header wash (subtle)
    static let headerWashOpacity: Double = 0.14
    static let headerWashBlur: CGFloat = 18
    static let headerWashHeight: CGFloat = 220

    // MARK: - Card styling helpers
    static let cardStroke = Color.black.opacity(0.05)

    // MARK: - Tile icon chips
    static func chipFill(for title: String) -> AnyShapeStyle {
        switch title {
        case "Invoices":
            return AnyShapeStyle(blueTint)

        case "Estimates":
            return AnyShapeStyle(greenTint)

        case "Bookings":
            // Brand-blue lane (scheduling)
            return AnyShapeStyle(blueTint)

        case "Customers", "Clients":
            // Slight green lean (people/customer)
            return AnyShapeStyle(greenTint)

        case "Requests", "Jobs", "New Request":
            // Neutral brand wash
            return AnyShapeStyle(brandGradient.opacity(0.18))

        case "Contracts":
                return AnyShapeStyle(brandBlue.opacity(0.10).blendMode(.normal)) // subtle

        case "Inventory", "Saved Items":
            // Light neutral
            return AnyShapeStyle(Color.black.opacity(0.06))
            

        case "Client Portal":
            return AnyShapeStyle(brandGradient.opacity(0.22))
            
        

        default:
            return AnyShapeStyle(Color.black.opacity(0.06))
        }
    }

    // MARK: - Stat accent strip
    static func statAccent(for title: String) -> LinearGradient {
        // Optional: you can vary the accent per stat if you want.
        // Keeping it consistent reads “brand” more than “rainbow”.
        return brandGradient
    }
}
extension SBWTheme {

    // MARK: - Status colors (semantic)
    static let statusPaid     = brandGreen
    static let statusUnpaid   = Color.orange
    static let statusDraft    = Color.gray
    static let statusSent     = brandBlue
    static let statusAccepted = brandGreen
    static let statusDeclined = Color.red

    static func chip(forStatus text: String) -> (fg: Color, bg: Color) {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        switch key {
        case "PAID":
            return (statusPaid, statusPaid.opacity(0.16))
        case "UNPAID":
            return (statusUnpaid, statusUnpaid.opacity(0.16))

        case "DRAFT":
            return (statusDraft, statusDraft.opacity(0.16))
        case "SENT":
            return (statusSent, statusSent.opacity(0.16))
        case "ACCEPTED":
            return (statusAccepted, statusAccepted.opacity(0.16))
        case "DECLINED":
            return (statusDeclined, statusDeclined.opacity(0.16))
        case "SCHEDULED":
            return (brandBlue, brandBlue.opacity(0.12))
        case "ACTIVE":
            return (brandGreen, brandGreen.opacity(0.12))
        case "COMPLETED":
            return (brandGreen, brandGreen.opacity(0.16))
        case "CANCELED":
            return (Color.red, Color.red.opacity(0.14))


        default:
            return (.secondary, Color.black.opacity(0.06))
        }
    }
    
}
