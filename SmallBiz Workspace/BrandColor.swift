//
//  BrandColor.swift
//  SmallBiz Workspace
//

import SwiftUI
import UIKit

/// A business's own brand color: what its clients see on invoices, the
/// portal, the booking page, its website and emails. Separate from the app's
/// Evergreen (SBWTheme), which is ours and never shown to a business's
/// clients by default.
enum BrandColor {
    /// When the owner hasn't picked one: a neutral that suits any business
    /// and doesn't look like SmallBiz Workspace.
    static let defaultHex = "#3A3A3C"

    /// Ready-made choices, all dark enough for white text.
    static let presets: [(name: String, hex: String)] = [
        ("Navy", "#1F4E8C"), ("Evergreen", "#0E5A47"), ("Brick", "#B3261E"), ("Orange", "#AD4E0F"),
        ("Plum", "#6B3FA0"), ("Teal", "#0F6E7C"), ("Charcoal", "#3A3A3C"), ("Berry", "#B0154F"),
    ]

    /// "#RRGGBB", or nil for anything that isn't a color.
    static func normalize(_ raw: String?) -> String? {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return nil }
        return "#" + s
    }

    /// The business's color, or the default.
    static func resolved(_ hex: String?) -> String { normalize(hex) ?? defaultHex }

    /// Darkened (same hue) until white text on it passes WCAG AA (4.5:1).
    /// Everything with white text on the brand uses this, so a pastel pick
    /// still gives readable buttons.
    static func readableOnWhite(_ hex: String) -> String {
        var (r, g, b) = components(resolved(hex))
        var guardCount = 0
        while contrastWithWhite(r, g, b) < 4.5, guardCount < 40 {
            r *= 0.94; g *= 0.94; b *= 0.94
            guardCount += 1
        }
        return hexString(r, g, b)
    }

    /// Whether `readableOnWhite` had to change it.
    static func needsDarkening(_ hex: String) -> Bool {
        readableOnWhite(hex) != resolved(hex)
    }

    /// A pale wash of the color over white, for table headers and soft areas.
    static func tint(_ hex: String, amount: Double = 0.10) -> String {
        let (r, g, b) = components(resolved(hex))
        return hexString(1 - (1 - r) * amount, 1 - (1 - g) * amount, 1 - (1 - b) * amount)
    }

    static func color(_ hex: String?) -> Color { Color(uiColor(hex)) }

    static func uiColor(_ hex: String?) -> UIColor {
        let (r, g, b) = components(resolved(hex))
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func hex(from color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return hexString(Double(r), Double(g), Double(b))
    }

    /// The logo's main color: the most common strong color, ignoring
    /// white, black, grays and transparency. Nil if the logo has none.
    static func fromLogo(_ data: Data) -> String? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        struct Bucket { var count = 0; var r = 0.0, g = 0.0, b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.6 else { continue }
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard saturation > 0.25, maxC > 0.15, maxC < 0.98 || saturation > 0.5 else { continue }
            let key = Int(r * 5) * 36 + Int(g * 5) * 6 + Int(b * 5)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1; bucket.r += r; bucket.g += g; bucket.b += b
            buckets[key] = bucket
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }), best.count >= 4 else { return nil }
        let n = Double(best.count)
        return readableOnWhite(hexString(best.r / n, best.g / n, best.b / n))
    }

    // MARK: - Math

    private static func components(_ hex: String) -> (Double, Double, Double) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x3A3A3C
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private static func hexString(_ r: Double, _ g: Double, _ b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    private static func contrastWithWhite(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return 1.05 / (l + 0.05)
    }
}
