import SwiftUI
import UIKit

extension Font {
    /// A system font at an exact point size that still responds to Dynamic Type.
    ///
    /// `Font.system(size:)` is fixed: a user who has set larger text gets the same
    /// small type as everyone else. The obvious fix — swapping to a text style like
    /// `.body` — also changes the size, so it can't be applied mechanically across
    /// screens without re-checking every layout.
    ///
    /// This keeps the designed size at the default text setting and scales from
    /// there, so existing layouts are unchanged for most users while larger-text
    /// settings finally do something.
    ///
    /// `relativeTo` picks the scaling curve: headings grow more slowly than body
    /// text, captions more quickly. Match it to the role, not the size.
    ///
    /// Prefer a plain text style (`.headline`, `.footnote`) for new code. This
    /// exists to make existing fixed sizes accessible without redesigning them.
    static func scaledSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let metrics = UIFontMetrics(forTextStyle: textStyle.uiKitTextStyle)
        return .system(size: metrics.scaledValue(for: size), weight: weight)
    }
}

extension Font.TextStyle {
    var uiKitTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
