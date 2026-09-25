import XCTest
import UIKit
@testable import SmallBizWorkspace

/// A business's brand color: what its clients see. White text on it must
/// stay readable whatever the owner picks, the default isn't ours, and
/// "Match my logo" finds the logo's color, not its white background.
final class BrandColorTests: XCTestCase {

    func testNormalizesTheWaysPeopleWriteAColor() {
        XCTAssertEqual(BrandColor.normalize("#1f4e8c"), "#1F4E8C")
        XCTAssertEqual(BrandColor.normalize("1F4E8C"), "#1F4E8C")
        XCTAssertEqual(BrandColor.normalize("#abc"), "#AABBCC")
        XCTAssertNil(BrandColor.normalize("blue"))
        XCTAssertNil(BrandColor.normalize(nil))
    }

    func testTheDefaultIsNeutralNotOurs() {
        XCTAssertEqual(BrandColor.resolved(nil), "#3A3A3C")
        XCTAssertNotEqual(BrandColor.defaultHex, "#0E5A47")
    }

    func testEveryPresetTakesWhiteTextAsIs() {
        for preset in BrandColor.presets {
            XCTAssertFalse(BrandColor.needsDarkening(preset.hex), "\(preset.name) \(preset.hex) is too light for white text")
        }
    }

    func testAPastelIsDarkenedUntilWhiteTextReads() {
        let pastel = "#9FE1CB"
        XCTAssertTrue(BrandColor.needsDarkening(pastel))
        let fixed = BrandColor.readableOnWhite(pastel)
        XCTAssertFalse(BrandColor.needsDarkening(fixed))
    }

    func testMatchMyLogoFindsTheLogoColorNotTheBackground() {
        let size = CGSize(width: 64, height: 64)
        let logo = UIGraphicsImageRenderer(size: size).pngData { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.12, green: 0.31, blue: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(x: 12, y: 12, width: 40, height: 40))
        }
        let found = try? XCTUnwrap(BrandColor.fromLogo(logo))
        XCTAssertNotNil(found)
        XCTAssertFalse(BrandColor.needsDarkening(found ?? "#FFFFFF"))
        // Blue dominant, not gray or white.
        let value = UInt32(found!.dropFirst(), radix: 16)!
        XCTAssertGreaterThan(value & 0xFF, (value >> 16) & 0xFF)
    }

    func testAGrayLogoHasNoColorToMatch() {
        let size = CGSize(width: 32, height: 32)
        let logo = UIGraphicsImageRenderer(size: size).pngData { ctx in
            UIColor.darkGray.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertNil(BrandColor.fromLogo(logo))
    }
}
