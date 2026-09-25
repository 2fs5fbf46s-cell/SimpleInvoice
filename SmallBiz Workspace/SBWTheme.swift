//
//  SBWTheme.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 2/1/26.
//

import Foundation
import SwiftUI
import UIKit

enum SBWTheme {
    // MARK: - Evergreen brand
    //
    // One brand hue (Evergreen) plus amber for "needs you". It replaced a
    // blue/green pair whose blue read as the system default and whose green
    // collided with "paid". Colors that text or buttons use have a lighter
    // dark-mode shade; Evergreen itself is too dark to read on black.

    /// The mark's own green: app icon, logo tile, launch screen. Same in both modes.
    static let evergreen = Color(hex: 0x0E5A47)

    /// Buttons, links, Next-step labels, selected tabs, key numbers.
    static let brand = dynamic(light: 0x0E6B53, dark: 0x4CC79E)
    /// Behind white text (filled buttons). Deeper than `brand` in dark mode,
    /// where the text shade is too light for white on top.
    static let brandFill = dynamic(light: 0x0E6B53, dark: 0x1F8A6C)
    /// Pale brand fill behind chips and selected rows.
    static let brandTint = brand.opacity(0.12)

    /// "Needs you": warnings, due soon, part paid.
    static let attention = dynamic(light: 0xB8740A, dark: 0xF2B544)

    /// Paid, signed, done. Brighter than the brand so a paid pill never
    /// reads as a button.
    static let success = dynamic(light: 0x1E9A5A, dark: 0x45D483)
    /// Behind white text.
    static let successFill = dynamic(light: 0x1E8A50, dark: 0x1E8A50)

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x0E5A47), Color(hex: 0x1F8A6C)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Header wash (subtle)
    static let headerWashOpacity: Double = 0.16
    static let headerWashBlur: CGFloat = 44
    static let headerWashHeight: CGFloat = 300

    // MARK: - Card styling helpers
    static let cardStroke = Color.primary.opacity(0.08)

    // MARK: - Header wash helper (for list screens)
    static func headerWash() -> some View {
        LinearGradient(colors: [Color(hex: 0x1F8A6C), Color(hex: 0x7ED6B4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(headerWashOpacity)
            .blur(radius: headerWashBlur)
            .frame(height: headerWashHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: - Tile icon chips
    static func chipFill(for title: String) -> AnyShapeStyle {
        switch title {
        case "Expenses":
            // Money going out: amber, apart from the green of money in.
            return AnyShapeStyle(attention.opacity(0.14))
        case "Inventory", "Saved Items":
            return AnyShapeStyle(Color.primary.opacity(0.06))
        default:
            // One brand lane; the icon says what it is.
            return AnyShapeStyle(brandTint)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension SBWTheme {

    // MARK: - Status colors (semantic)
    static let statusPaid     = success
    static let statusUnpaid   = attention
    static let statusDraft    = Color.gray
    static let statusSent     = brand
    static let statusAccepted = success
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
            return (brand, brand.opacity(0.10))
        case "ACTIVE":
            return (success, success.opacity(0.10))
        case "COMPLETED":
            return (success, success.opacity(0.12))
        case "CANCELED", "CANCELLED":
            return (Color.red, Color.red.opacity(0.12))
        case "SIGNED":
            return (success, success.opacity(0.12))
        case "OVERDUE":
            return (Color.red, Color.red.opacity(0.12))
        case "PART PAID":
            return (attention, attention.opacity(0.14))


        default:
            return (.secondary, Color.primary.opacity(0.06))
        }
    }
    
}

// MARK: - Navigation chrome

extension View {
    /// Give the navigation bar something to sit on.
    ///
    /// Every screen layers its own background — a grouped-background fill plus a
    /// brand gradient wash, both with `.ignoresSafeArea()` — under a `ScrollView`.
    /// With no toolbar background of its own, the bar was fully transparent, so
    /// scrolled content rendered straight through it: on the Dashboard, the Quick
    /// Start copy slid up and overlapped the word "Dashboard" at full opacity.
    ///
    /// Visibility stays automatic, so the bar is still clear at the top of a
    /// scroll and gains its backdrop only once content passes underneath.
    func sbwNavigationBarBackdrop() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
