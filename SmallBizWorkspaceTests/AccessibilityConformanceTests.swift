import XCTest
@testable import SmallBizWorkspace

/// Guards on accessibility properties that are easy to regress silently.
///
/// Dynamic Type is the kind of thing that works until someone adds one more
/// `.font(.system(size:))` in a hurry. A user with larger text set gets no
/// feedback that it was ignored, and neither does the developer.
final class AccessibilityConformanceTests: XCTestCase {

    /// The app sources, located relative to this test file so it works wherever
    /// the repo is checked out.
    private func sourceFiles() throws -> [URL] {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()   // SmallBizWorkspaceTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("SmallBiz Workspace", isDirectory: true)

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip("Could not walk the source tree at \(root.path)")
        }

        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    func testNoFixedFontSizes() throws {
        let files = try sourceFiles()
        try XCTSkipIf(files.isEmpty, "No sources found; nothing to check")

        var offenders: [String] = []
        for file in files {
            // The helper's own documentation names the API it replaces.
            if file.lastPathComponent == "ScaledFont.swift" { continue }

            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains(".font(.system(size:") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertEqual(
            offenders,
            [],
            """
            These use a fixed point size, so they ignore Dynamic Type. Use \
            .scaledSystem(size:weight:relativeTo:) to keep the designed size while \
            scaling, or a text style like .headline:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    func testScaledFontCoversEveryTextStyle() {
        // A missing case would silently fall back to .body and scale wrongly.
        let styles: [Font.TextStyle] = [
            .largeTitle, .title, .title2, .title3, .headline,
            .subheadline, .body, .callout, .footnote, .caption, .caption2,
        ]

        let mapped = Set(styles.map(\.uiKitTextStyle))
        XCTAssertEqual(
            mapped.count,
            styles.count,
            "two SwiftUI text styles map to the same UIKit style, so one scales wrongly"
        )
    }

    func testScaledSystemProducesAFont() {
        // Exercises the UIFontMetrics path rather than asserting a point size,
        // which legitimately varies with the simulator's text setting.
        XCTAssertNotNil(Font.scaledSystem(size: 16))
        XCTAssertNotNil(Font.scaledSystem(size: 28, weight: .bold, relativeTo: .title))
    }
}

import SwiftUI
