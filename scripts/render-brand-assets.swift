// Renders the app icon and launch logo from SBWLogoMark.swift, the same
// drawing the app shows, so they can't drift apart.
//
//   ./scripts/render-brand-assets.sh
//
import SwiftUI
import AppKit

enum SBWTheme {
    static let evergreen = Color(red: 0x0E / 255, green: 0x5A / 255, blue: 0x47 / 255)
}

@MainActor
func png<V: View>(_ view: V, size: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed: \(path)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

@main
struct RenderBrandAssets {
    @MainActor
    static func main() {
    let args = CommandLine.arguments
    let iconDir = args[1], launchDir = args[2]
    png(SBWLogoMark(tile: .square), size: 1024, to: "\(iconDir)/AppIcon-1024.png")
    for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
        png(SBWLogoMark(), size: CGFloat(76 * scale), to: "\(launchDir)/LaunchLogo\(suffix).png")
    }
    }
}
