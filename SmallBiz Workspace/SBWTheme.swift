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

    // Derived for dark mode (softened, non-neon)
    static let brandBlueSoft  = Color(red: 0.16, green: 0.46, blue: 0.78)
    static let brandTealSoft  = Color(red: 0.18, green: 0.60, blue: 0.58)
    static let brandGreenSoft = Color(red: 0.22, green: 0.72, blue: 0.40)

    static let brandGradient = LinearGradient(
        colors: [brandBlueSoft, brandTealSoft, brandGreenSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Subtle tints for chips/backgrounds
    static let blueTint  = brandBlue.opacity(0.12)
    static let greenTint = brandGreen.opacity(0.12)

    // MARK: - Header wash (subtle)
    static let headerWashOpacity: Double = 0.19
    static let headerWashBlur: CGFloat = 44
    static let headerWashHeight: CGFloat = 300

    // MARK: - Card styling helpers
    static let cardStroke = Color.primary.opacity(0.08)

    // MARK: - Header wash helper (for list screens)
    static func headerWash() -> some View {
        brandGradient
            .opacity(headerWashOpacity)
            .blur(radius: headerWashBlur)
            .frame(height: headerWashHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: - Optional card glow (future use)
    static func cardGlow() -> some View {
        brandGradient
            .opacity(0.05)
            .blur(radius: 24)
    }

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
            return AnyShapeStyle(brandGradient.opacity(0.14))

        case "Contracts":
                return AnyShapeStyle(brandBlue.opacity(0.10).blendMode(.normal)) // subtle

        case "Inventory", "Saved Items":
            // Light neutral
            return AnyShapeStyle(Color.primary.opacity(0.06))
            

        case "Client Portal":
            return AnyShapeStyle(brandGradient.opacity(0.18))
            
        

        default:
            return AnyShapeStyle(Color.primary.opacity(0.06))
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
            return (statusPaid, statusPaid.opacity(0.12))
        case "UNPAID":
            return (statusUnpaid, statusUnpaid.opacity(0.12))

        case "DRAFT":
            return (statusDraft, statusDraft.opacity(0.12))
        case "SENT":
            return (statusSent, statusSent.opacity(0.12))
        case "ACCEPTED":
            return (statusAccepted, statusAccepted.opacity(0.12))
        case "DECLINED":
            return (statusDeclined, statusDeclined.opacity(0.12))
        case "SCHEDULED":
            return (brandBlue, brandBlue.opacity(0.10))
        case "ACTIVE":
            return (brandGreen, brandGreen.opacity(0.10))
        case "COMPLETED":
            return (brandGreen, brandGreen.opacity(0.12))
        case "CANCELED":
            return (Color.red, Color.red.opacity(0.12))


        default:
            return (.secondary, Color.primary.opacity(0.06))
        }
    }
    
}
