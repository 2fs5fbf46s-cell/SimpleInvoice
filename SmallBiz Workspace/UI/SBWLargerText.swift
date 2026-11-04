import SwiftUI

/// Layout for owners who use Larger Text (Settings › Accessibility › Display
/// & Text Size). Every helper here leaves the standard sizes exactly as they
/// were and only steps in at the accessibility sizes.
///
/// At those sizes the app used to squeeze rows built for the default size:
/// amounts broke across lines ("$1,850." over "00"), times stacked a digit
/// at a time, names cut to "Oakridg…", and three tiles side by side showed
/// "Owe…" and "$2,91…". The fix is the one iOS's own apps use: what sat
/// side by side goes one under the other, and nothing important is cut off.

/// Side by side at standard sizes, one under the other at accessibility sizes,
/// or the reverse with `normally: .vertical`. A row's name and amount use the
/// first; the amount-over-status column inside it uses the second, so at large
/// sizes the amount and its status share a line under the name.
struct SBWAdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size

    var normally: Axis = .horizontal
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let large = size.isAccessibilitySize
        let horizontal = (normally == .horizontal) != large
        let layout = horizontal
            ? AnyLayout(HStackLayout(alignment: large ? .center : verticalAlignment, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: large ? .leading : horizontalAlignment, spacing: spacing))
        // Stacked, it takes the row's width so it starts at the leading edge.
        // Without the spacer that did this side by side, rows between an icon
        // and a chevron drifted to the middle.
        if large && normally == .horizontal {
            layout { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            layout { content }
        }
    }
}

extension View {
    /// `lineLimit(lines)` at standard sizes. At accessibility sizes the text
    /// may wrap instead: a name cut to its first few letters can't be read
    /// however large it is.
    func sbwLineLimit(_ lines: Int) -> some View {
        modifier(SBWLineLimit(lines: lines))
    }

    /// An amount of money: one line always, shrinking before it would wrap.
    /// Left to wrap, "$1,850.00" broke after the decimal point.
    func sbwAmount() -> some View {
        lineLimit(1)
            .minimumScaleFactor(0.5)
            .monospacedDigit()
    }

    /// For text inside a fixed shape, like initials in a circle or a time in
    /// a column: it grows with Larger Text, but only so far, rather than
    /// turning into "…" or one character per line. VoiceOver still reads it
    /// in full.
    func sbwCappedType(_ cap: DynamicTypeSize = .xxxLarge) -> some View {
        dynamicTypeSize(...cap)
    }

    /// Left out at accessibility sizes. For words the screen already says
    /// elsewhere, like the step names under a status track, whose pill
    /// names the current step: three across, they broke into syllables.
    func sbwHiddenWhenLarge() -> some View {
        modifier(SBWHiddenWhenLarge())
    }
}

private struct SBWHiddenWhenLarge: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size

    @ViewBuilder
    func body(content: Content) -> some View {
        if !size.isAccessibilitySize { content }
    }
}

private struct SBWLineLimit: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    let lines: Int

    func body(content: Content) -> some View {
        content.lineLimit(size.isAccessibilitySize ? lines + 3 : lines)
    }
}

/// A list's search box. Its hint ("Search name, email, phone, address")
/// shrank to fit at large sizes until it was the smallest text on screen, so
/// there it's just "Search".
struct SBWSearchTextField: View {
    @Environment(\.dynamicTypeSize) private var size
    let prompt: String
    @Binding var text: String

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        TextField(size.isAccessibilitySize ? "Search" : prompt, text: $text)
    }
}

/// The words inside a summary tile ("Owed to you", "$2,910.00", "3
/// invoices"). Put tiles in an `SBWAdaptiveStack` and they stack at
/// accessibility sizes; there each tile has the width to put its label and
/// amount on one line, where three abreast showed "Owe…" over "$2,91…".
struct SBWTileText: View {
    @Environment(\.dynamicTypeSize) private var size

    let title: String
    let value: String
    var detail: String? = nil
    var valueFont: Font = .headline
    var titleColor: Color = .secondary
    var valueColor: Color = .primary
    var detailColor: Color = .secondary
    /// Off where the tiles sit in a fixed header (Money), so that stacked
    /// they don't push the list off the screen.
    var showsDetailWhenLarge = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if size.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleText.fixedSize()
                        Spacer(minLength: 0)
                        valueText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        valueText
                    }
                }
                if showsDetailWhenLarge, let detail {
                    detailText(detail)
                }
            } else {
                titleText.lineLimit(1)
                valueText
                if let detail { detailText(detail).lineLimit(1) }
            }
        }
    }

    private var titleText: some View {
        Text(title).font(.caption).foregroundStyle(titleColor)
    }

    private var valueText: some View {
        Text(value).font(valueFont).foregroundStyle(valueColor).sbwAmount()
    }

    private func detailText(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(detailColor)
    }
}

/// The `Spacer` between a row's two sides inside an `SBWAdaptiveStack`. Once
/// the row stacks, a Spacer turned into a tall empty band in the middle of it.
struct SBWRowSpacer: View {
    @Environment(\.dynamicTypeSize) private var size
    var minLength: CGFloat = 8

    var body: some View {
        if !size.isAccessibilitySize {
            Spacer(minLength: minLength)
        }
    }
}

/// A row of icon-over-label buttons (Call, Text, Directions…): four across,
/// or two by two at accessibility sizes, where four across broke
/// "Directions" over two lines.
struct SBWActionGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    @ViewBuilder var content: Content

    var body: some View {
        if size.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 14) {
                content
            }
        } else {
            HStack { content }
        }
    }
}
