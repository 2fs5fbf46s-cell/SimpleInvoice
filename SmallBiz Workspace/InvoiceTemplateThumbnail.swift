import SwiftUI

struct InvoiceTemplateThumbnail: View {
    let templateKey: InvoiceTemplateKey

    var body: some View {
        let style = styleForTemplate(templateKey)

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(alignment: .top) {
                headerBand(style: style)
            }
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let topInset = style.compact ? 12.0 : 16.0
                    let rowHeight = style.compact ? 5.0 : 6.0
                    let gap = style.compact ? 4.0 : 5.0

                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: topInset)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(style.strongLine)
                            .frame(width: width * 0.45, height: style.compact ? 4 : 5)
                            .padding(.horizontal, 8)
                            .padding(.bottom, style.compact ? 4 : 6)

                        VStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { idx in
                                ZStack(alignment: .leading) {
                                    if style.zebraRows && idx % 2 == 1 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(style.zebraFill)
                                            .frame(height: rowHeight + 2)
                                    }

                                    HStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(style.line)
                                            .frame(width: width * 0.36, height: rowHeight)
                                        Spacer(minLength: 2)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(style.line)
                                            .frame(width: width * 0.12, height: rowHeight)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(style.line)
                                            .frame(width: width * 0.16, height: rowHeight)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)

                        Spacer(minLength: 0)

                        Rectangle()
                            .fill(style.footerLine)
                            .frame(height: style.minimalLines ? 1 : 1.5)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                    .frame(width: width, height: height)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(style.outline, lineWidth: 1)
            )
            .frame(width: 76, height: 96)
            .accessibilityHidden(true)
    }

    private func headerBand(style: ThumbnailStyle) -> some View {
        Group {
            if let fill = style.headerFill {
                fill
            } else if let gradient = style.headerGradient {
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }
        }
        .frame(height: style.compact ? 16 : 20)
        .clipShape(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private struct ThumbnailStyle {
        let headerFill: Color?
        let headerGradient: [Color]?
        let zebraRows: Bool
        let minimalLines: Bool
        let compact: Bool
        let line: Color
        let strongLine: Color
        let footerLine: Color
        let zebraFill: Color
        let outline: Color
    }

    private func styleForTemplate(_ key: InvoiceTemplateKey) -> ThumbnailStyle {
        switch key {
        case .classic_business:
            return ThumbnailStyle(
                headerFill: nil,
                headerGradient: nil,
                zebraRows: false,
                minimalLines: false,
                compact: false,
                line: Color.gray.opacity(0.42),
                strongLine: Color.gray.opacity(0.55),
                footerLine: Color.gray.opacity(0.55),
                zebraFill: Color.gray.opacity(0.08),
                outline: Color.gray.opacity(0.30)
            )
        case .modern_clean:
            return ThumbnailStyle(
                headerFill: nil,
                headerGradient: nil,
                zebraRows: true,
                minimalLines: true,
                compact: false,
                line: Color.gray.opacity(0.32),
                strongLine: Color.gray.opacity(0.45),
                footerLine: Color.gray.opacity(0.45),
                zebraFill: Color.gray.opacity(0.12),
                outline: Color.gray.opacity(0.24)
            )
        case .bold_header:
            return ThumbnailStyle(
                headerFill: Color(red: 0.11, green: 0.15, blue: 0.21),
                headerGradient: nil,
                zebraRows: false,
                minimalLines: false,
                compact: false,
                line: Color.gray.opacity(0.42),
                strongLine: Color.gray.opacity(0.58),
                footerLine: Color.gray.opacity(0.58),
                zebraFill: Color.gray.opacity(0.08),
                outline: Color.gray.opacity(0.30)
            )
        case .minimal_compact:
            return ThumbnailStyle(
                headerFill: nil,
                headerGradient: nil,
                zebraRows: false,
                minimalLines: true,
                compact: true,
                line: Color.gray.opacity(0.34),
                strongLine: Color.gray.opacity(0.46),
                footerLine: Color.gray.opacity(0.46),
                zebraFill: Color.gray.opacity(0.10),
                outline: Color.gray.opacity(0.24)
            )
        case .creative_studio:
            return ThumbnailStyle(
                headerFill: nil,
                headerGradient: [
                    Color(red: 0.16, green: 0.49, blue: 0.97),
                    Color(red: 0.10, green: 0.66, blue: 0.41)
                ],
                zebraRows: true,
                minimalLines: true,
                compact: false,
                line: Color.gray.opacity(0.33),
                strongLine: Color.gray.opacity(0.46),
                footerLine: Color.gray.opacity(0.46),
                zebraFill: Color(red: 0.18, green: 0.52, blue: 0.94).opacity(0.16),
                outline: Color.gray.opacity(0.25)
            )
        case .contractor_trades:
            return ThumbnailStyle(
                headerFill: nil,
                headerGradient: nil,
                zebraRows: false,
                minimalLines: false,
                compact: false,
                line: Color.gray.opacity(0.44),
                strongLine: Color.gray.opacity(0.70),
                footerLine: Color.gray.opacity(0.70),
                zebraFill: Color.gray.opacity(0.08),
                outline: Color.gray.opacity(0.30)
            )
        }
    }
}
