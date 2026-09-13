import Foundation
import UIKit

enum InvoicePDFGenerator {

    static func preferredPDFFileName(for invoice: Invoice, customName: String? = nil) -> String {
        "\(preferredPDFBaseName(for: invoice, customName: customName)).pdf"
    }

    static func preferredPDFBaseName(for invoice: Invoice, customName: String? = nil) -> String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return sanitizedPDFBaseName(custom, fallback: invoice.documentType == "estimate" ? "Estimate" : "Invoice")
        }

        let prefix = invoice.documentType == "estimate" ? "Estimate" : "Invoice"
        let number = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = number.isEmpty ? String(invoice.id.uuidString.prefix(8)) : number
        return sanitizedPDFBaseName("\(prefix)_\(identifier)", fallback: prefix)
    }

    static func sanitizedPDFBaseName(_ name: String, fallback: String = "Invoice") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPDFExtension: String
        if (trimmed as NSString).pathExtension.lowercased() == "pdf" {
            withoutPDFExtension = (trimmed as NSString).deletingPathExtension
        } else {
            withoutPDFExtension = trimmed
        }

        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let controlCharacters = CharacterSet.controlCharacters
        var result = ""
        var lastWasSeparator = false

        func appendSeparator(_ separator: Character) {
            guard !result.isEmpty, !lastWasSeparator else { return }
            result.append(separator)
            lastWasSeparator = true
        }

        for scalar in withoutPDFExtension.unicodeScalars {
            if invalidCharacters.contains(scalar) || controlCharacters.contains(scalar) {
                appendSeparator("-")
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendSeparator("_")
            } else {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            }
        }

        let sanitized = result.trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
        return sanitized.isEmpty ? fallback : sanitized
    }

    /// Lay out and rasterize the document.
    ///
    /// Takes a plain snapshot rather than the SwiftData model, so it can run off
    /// the main actor — see `InvoiceRenderModel`. The parameter keeps the name
    /// `invoice` because every expression in the body reads the same either way.
    nonisolated static func makePDFData(
        invoice: InvoiceRenderModel,
        business: BusinessSnapshot,
        templateKey: InvoiceTemplateKey = .modern_clean
    ) -> Data {

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let isEstimate = (invoice.documentType == "estimate")
        let docTitle = isEstimate ? "ESTIMATE" : "INVOICE"

        struct Style {
            let margin: CGFloat
            let sectionGap: CGFloat
            let rowGap: CGFloat
            let baseRowHeight: CGFloat

            let titleFont: UIFont
            let bodyFont: UIFont
            let metaFont: UIFont
            let tableHeaderFont: UIFont
            let totalsFont: UIFont
            let totalsBoldFont: UIFont

            let primaryText: UIColor
            let secondaryText: UIColor
            let lineColor: UIColor

            let headerFill: UIColor?
            let headerGradient: (UIColor, UIColor)?
            let zebraRows: Bool
            let minimalLines: Bool

            let zebraFillColor: UIColor
            let strongerSeparators: Bool
        }

        func style(for templateKey: InvoiceTemplateKey) -> Style {
            switch templateKey {
            case .classic_business:
                return Style(
                    margin: 36,
                    sectionGap: 16,
                    rowGap: 6,
                    baseRowHeight: 18,
                    titleFont: .systemFont(ofSize: 28, weight: .bold),
                    bodyFont: .systemFont(ofSize: 12, weight: .regular),
                    metaFont: .systemFont(ofSize: 12, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 11, weight: .semibold),
                    totalsFont: .systemFont(ofSize: 12, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 12, weight: .bold),
                    primaryText: .black,
                    secondaryText: .darkGray,
                    lineColor: UIColor(white: 0.85, alpha: 1.0),
                    headerFill: nil,
                    headerGradient: nil,
                    zebraRows: false,
                    minimalLines: false,
                    zebraFillColor: UIColor(white: 0.96, alpha: 1.0),
                    strongerSeparators: false
                )

            case .modern_clean:
                return Style(
                    margin: 42,
                    sectionGap: 18,
                    rowGap: 7,
                    baseRowHeight: 18,
                    titleFont: .systemFont(ofSize: 29, weight: .bold),
                    bodyFont: .systemFont(ofSize: 12, weight: .regular),
                    metaFont: .systemFont(ofSize: 11.5, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 11, weight: .semibold),
                    totalsFont: .systemFont(ofSize: 12, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 12, weight: .bold),
                    primaryText: .black,
                    secondaryText: UIColor(white: 0.35, alpha: 1.0),
                    lineColor: UIColor(white: 0.90, alpha: 1.0),
                    headerFill: nil,
                    headerGradient: nil,
                    zebraRows: true,
                    minimalLines: true,
                    zebraFillColor: UIColor(white: 0.965, alpha: 1.0),
                    strongerSeparators: false
                )

            case .bold_header:
                return Style(
                    margin: 36,
                    sectionGap: 16,
                    rowGap: 6,
                    baseRowHeight: 18,
                    titleFont: .systemFont(ofSize: 28, weight: .bold),
                    bodyFont: .systemFont(ofSize: 12, weight: .regular),
                    metaFont: .systemFont(ofSize: 12, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 11, weight: .semibold),
                    totalsFont: .systemFont(ofSize: 12, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 12, weight: .bold),
                    primaryText: .black,
                    secondaryText: .darkGray,
                    lineColor: UIColor(white: 0.82, alpha: 1.0),
                    headerFill: UIColor(red: 0.10, green: 0.14, blue: 0.21, alpha: 1.0),
                    headerGradient: nil,
                    zebraRows: false,
                    minimalLines: false,
                    zebraFillColor: UIColor(white: 0.96, alpha: 1.0),
                    strongerSeparators: false
                )

            case .minimal_compact:
                return Style(
                    margin: 30,
                    sectionGap: 12,
                    rowGap: 4,
                    baseRowHeight: 15,
                    titleFont: .systemFont(ofSize: 24, weight: .bold),
                    bodyFont: .systemFont(ofSize: 10.5, weight: .regular),
                    metaFont: .systemFont(ofSize: 10.5, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 10, weight: .semibold),
                    totalsFont: .systemFont(ofSize: 11, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 11, weight: .bold),
                    primaryText: .black,
                    secondaryText: UIColor(white: 0.33, alpha: 1.0),
                    lineColor: UIColor(white: 0.90, alpha: 1.0),
                    headerFill: nil,
                    headerGradient: nil,
                    zebraRows: false,
                    minimalLines: true,
                    zebraFillColor: UIColor(white: 0.965, alpha: 1.0),
                    strongerSeparators: false
                )

            case .creative_studio:
                return Style(
                    margin: 40,
                    sectionGap: 18,
                    rowGap: 7,
                    baseRowHeight: 18,
                    titleFont: .systemFont(ofSize: 28, weight: .bold),
                    bodyFont: .systemFont(ofSize: 12, weight: .regular),
                    metaFont: .systemFont(ofSize: 11.5, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 11, weight: .semibold),
                    totalsFont: .systemFont(ofSize: 12, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 12, weight: .bold),
                    primaryText: UIColor(white: 0.08, alpha: 1.0),
                    secondaryText: UIColor(white: 0.30, alpha: 1.0),
                    lineColor: UIColor(white: 0.88, alpha: 1.0),
                    headerFill: nil,
                    headerGradient: (
                        UIColor(red: 0.16, green: 0.49, blue: 0.97, alpha: 0.32),
                        UIColor(red: 0.10, green: 0.66, blue: 0.41, alpha: 0.22)
                    ),
                    zebraRows: true,
                    minimalLines: true,
                    zebraFillColor: UIColor(red: 0.18, green: 0.52, blue: 0.94, alpha: 0.045),
                    strongerSeparators: false
                )

            case .contractor_trades:
                return Style(
                    margin: 36,
                    sectionGap: 16,
                    rowGap: 6,
                    baseRowHeight: 18,
                    titleFont: .systemFont(ofSize: 28, weight: .bold),
                    bodyFont: .systemFont(ofSize: 12, weight: .regular),
                    metaFont: .systemFont(ofSize: 12, weight: .regular),
                    tableHeaderFont: .systemFont(ofSize: 11.5, weight: .bold),
                    totalsFont: .systemFont(ofSize: 12, weight: .regular),
                    totalsBoldFont: .systemFont(ofSize: 12, weight: .bold),
                    primaryText: .black,
                    secondaryText: .darkGray,
                    lineColor: UIColor(white: 0.78, alpha: 1.0),
                    headerFill: nil,
                    headerGradient: nil,
                    zebraRows: false,
                    minimalLines: false,
                    zebraFillColor: UIColor(white: 0.96, alpha: 1.0),
                    strongerSeparators: true
                )
            }
        }

        let style = style(for: templateKey)
        let titleColor: UIColor = (style.headerFill != nil) ? .white : style.primaryText

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let paidColor = UIColor(red: 0.10, green: 0.60, blue: 0.25, alpha: 1.0)
        let unpaidColor = UIColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1.0)
        let overdueColor = UIColor(red: 0.75, green: 0.10, blue: 0.10, alpha: 1.0)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = style.margin

            func drawHeaderBackgroundIfNeeded() {
                if let fill = style.headerFill {
                    let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: style.margin + 44)
                    ctx.cgContext.saveGState()
                    fill.setFill()
                    ctx.cgContext.fill(headerRect)
                    ctx.cgContext.restoreGState()
                    return
                }

                guard let gradientColors = style.headerGradient else { return }
                let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 120)
                let cgColors = [gradientColors.0.cgColor, gradientColors.1.cgColor] as CFArray

                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: cgColors,
                    locations: [0.0, 1.0]
                ) else {
                    return
                }

                ctx.cgContext.saveGState()
                ctx.cgContext.addRect(headerRect)
                ctx.cgContext.clip()
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: pageWidth, y: headerRect.maxY),
                    options: []
                )
                ctx.cgContext.restoreGState()
            }

            drawHeaderBackgroundIfNeeded()

            func drawText(_ text: String,
                          font: UIFont,
                          rect: CGRect,
                          color: UIColor = UIColor.black,
                          alignment: NSTextAlignment = .left,
                          lineBreak: NSLineBreakMode = .byWordWrapping) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = lineBreak
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            func drawAttributedText(_ text: String,
                                    rect: CGRect,
                                    attributes: [NSAttributedString.Key: Any]) {
                (text as NSString).draw(in: rect, withAttributes: attributes)
            }

            func drawLine(_ lineY: CGFloat, thickness: CGFloat = 1, alpha: CGFloat = 1) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: style.margin, y: lineY))
                path.addLine(to: CGPoint(x: pageWidth - style.margin, y: lineY))
                style.lineColor.withAlphaComponent(alpha).setStroke()
                path.lineWidth = thickness
                path.stroke()
            }

            func money(_ value: Double) -> String {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
                return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
            }

            func formatDate(_ d: Date) -> String {
                let df = DateFormatter()
                df.dateStyle = .medium
                return df.string(from: d)
            }

            func beginNewPageIfNeeded(neededSpace: CGFloat) {
                let bottomMargin: CGFloat = max(48, style.margin)
                if y + neededSpace > pageHeight - bottomMargin {
                    ctx.beginPage()
                    drawHeaderBackgroundIfNeeded()
                    y = style.margin
                }
            }

            func trimmed(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            func normalizedMultilineText(_ text: String) -> String {
                text
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .replacingOccurrences(of: "\u{2028}", with: "\n")
                    .replacingOccurrences(of: "\u{2029}", with: "\n")
            }

            func textHeight(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                return ceil(rect.height)
            }

            func largestPrefixThatFits(
                text: String,
                width: CGFloat,
                maxHeight: CGFloat,
                attributes: [NSAttributedString.Key: Any]
            ) -> String {
                let source = text as NSString
                let length = source.length
                guard length > 0 else { return "" }

                var low = 1
                var high = length
                var best = 0

                while low <= high {
                    let mid = (low + high) / 2
                    let candidate = source.substring(to: mid)
                    let h = textHeight(candidate, width: width, attributes: attributes)
                    if h <= maxHeight {
                        best = mid
                        low = mid + 1
                    } else {
                        high = mid - 1
                    }
                }

                guard best > 0 else { return "" }
                var prefix = source.substring(to: best)

                // Prefer a clean break at newline/space if possible.
                if best < length {
                    let breakSet = CharacterSet.whitespacesAndNewlines
                    let prefixNSString = prefix as NSString
                    let range = prefixNSString.rangeOfCharacter(from: breakSet, options: .backwards)
                    if range.location != NSNotFound, range.location > 0 {
                        prefix = prefixNSString.substring(to: range.location)
                    }
                }

                return prefix
            }

            func drawWatermarkIfNeeded() {
                let now = Date()
                let isOverdue = !invoice.isPaid && invoice.dueDate < now

                let text: String?
                let color: UIColor

                if isEstimate {
                    text = "ESTIMATE"
                    color = UIColor.black.withAlphaComponent(0.06)
                } else if invoice.isPaid {
                    text = "PAID"
                    color = paidColor.withAlphaComponent(0.12)
                } else if isOverdue {
                    text = "OVERDUE"
                    color = overdueColor.withAlphaComponent(0.10)
                } else {
                    text = nil
                    color = .clear
                }

                guard let text else { return }

                let watermarkFont = UIFont.systemFont(ofSize: 86, weight: .black)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: watermarkFont,
                    .foregroundColor: color
                ]

                let str = text as NSString
                let size = str.size(withAttributes: attrs)

                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: pageWidth / 2, y: pageHeight / 2)
                ctx.cgContext.rotate(by: -CGFloat.pi / 10)
                str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)
                ctx.cgContext.restoreGState()
            }

            drawWatermarkIfNeeded()

            // Header
            let hasLogo = (business.logoData != nil)
            let numberLabel = isEstimate ? "Estimate #:" : "Invoice #:"
            let numberText = "\(numberLabel) \(invoice.invoiceNumber)"
            var metaIncludesNumber = true

            func drawLogo(maxWidth: CGFloat, maxHeight: CGFloat, originX: CGFloat, originY: CGFloat) {
                guard let logoData = business.logoData,
                      let logoImage = UIImage(data: logoData) else { return }

                let imgAspect = logoImage.size.width / max(logoImage.size.height, 1)
                var width = imgAspect * maxHeight
                var height = maxHeight

                if width > maxWidth {
                    width = maxWidth
                    height = width / max(imgAspect, 0.001)
                }

                logoImage.draw(in: CGRect(x: originX, y: originY, width: width, height: height))
            }

            let bizName = trimmed(business.name)
            let bizEmail = trimmed(business.email)
            let bizPhone = trimmed(business.phone)
            let bizAddress = trimmed(business.address)

            let businessLines = [
                bizName,
                bizAddress,
                bizPhone,
                bizEmail
            ]
            .filter { !trimmed($0).isEmpty }
            .joined(separator: "\n")

            switch templateKey {
            case .classic_business, .contractor_trades:
                if hasLogo {
                    drawLogo(maxWidth: 170, maxHeight: 60, originX: style.margin, originY: y)
                }
                drawText(docTitle,
                         font: style.titleFont,
                         rect: CGRect(x: style.margin, y: y, width: pageWidth - (style.margin * 2), height: 34),
                         color: titleColor,
                         alignment: .right)

                let businessX: CGFloat = hasLogo ? style.margin + 190 : style.margin
                drawText(businessLines,
                         font: style.bodyFont,
                         rect: CGRect(x: businessX, y: y, width: 320, height: 90),
                         color: style.primaryText)
                y += hasLogo ? 106 : 96

            case .modern_clean:
                drawText(docTitle,
                         font: style.titleFont,
                         rect: CGRect(x: style.margin, y: y, width: pageWidth * 0.52, height: 34),
                         color: style.primaryText,
                         alignment: .left)

                if hasLogo {
                    drawLogo(
                        maxWidth: 120,
                        maxHeight: 44,
                        originX: pageWidth - style.margin - 120,
                        originY: y + 2
                    )
                }

                drawText(businessLines,
                         font: style.bodyFont,
                         rect: CGRect(
                            x: style.margin,
                            y: y + 38,
                            width: pageWidth - (style.margin * 2),
                            height: 70
                         ),
                         color: style.primaryText)
                y += hasLogo ? 100 : 92

            case .bold_header:
                drawText(docTitle,
                         font: style.titleFont,
                         rect: CGRect(x: style.margin, y: y - 2, width: pageWidth * 0.52, height: 34),
                         color: .white,
                         alignment: .left)
                drawText(numberText,
                         font: UIFont.systemFont(ofSize: style.metaFont.pointSize, weight: .semibold),
                         rect: CGRect(x: pageWidth - style.margin - 250, y: y + 4, width: 250, height: 18),
                         color: .white,
                         alignment: .right)
                metaIncludesNumber = false

                if hasLogo {
                    drawLogo(maxWidth: 140, maxHeight: 44, originX: style.margin, originY: y + 30)
                }
                let businessX = hasLogo ? style.margin + 150 : style.margin
                drawText(businessLines,
                         font: style.bodyFont,
                         rect: CGRect(x: businessX, y: y + 30, width: pageWidth - businessX - style.margin, height: 74),
                         color: UIColor.white.withAlphaComponent(0.88))
                y += hasLogo ? 98 : 90

            case .creative_studio:
                drawText(docTitle,
                         font: style.titleFont,
                         rect: CGRect(x: style.margin, y: y + 2, width: pageWidth * 0.50, height: 34),
                         color: style.primaryText,
                         alignment: .left)
                drawText(numberText,
                         font: UIFont.systemFont(ofSize: style.metaFont.pointSize, weight: .semibold),
                         rect: CGRect(x: pageWidth - style.margin - 250, y: y + 6, width: 250, height: 18),
                         color: style.primaryText,
                         alignment: .right)
                metaIncludesNumber = false

                if hasLogo {
                    drawLogo(
                        maxWidth: 112,
                        maxHeight: 42,
                        originX: pageWidth - style.margin - 112,
                        originY: y + 28
                    )
                }

                drawText(businessLines,
                         font: style.bodyFont,
                         rect: CGRect(
                            x: style.margin,
                            y: y + 44,
                            width: hasLogo ? (pageWidth - (style.margin * 2) - 126) : (pageWidth - (style.margin * 2)),
                            height: 64
                         ),
                         color: style.primaryText)
                y += hasLogo ? 104 : 96

            case .minimal_compact:
                if hasLogo {
                    drawLogo(maxWidth: 120, maxHeight: 42, originX: style.margin, originY: y)
                }
                drawText(docTitle,
                         font: style.titleFont,
                         rect: CGRect(x: style.margin, y: y, width: pageWidth - (style.margin * 2), height: 28),
                         color: style.primaryText,
                         alignment: .right)

                let businessX: CGFloat = hasLogo ? style.margin + 132 : style.margin
                drawText(businessLines,
                         font: style.bodyFont,
                         rect: CGRect(x: businessX, y: y + 4, width: pageWidth - businessX - style.margin, height: 58),
                         color: style.primaryText)
                y += hasLogo ? 74 : 66
            }

            drawLine(
                y,
                thickness: style.strongerSeparators ? 1.25 : 1,
                alpha: style.minimalLines ? 0.8 : 1
            )
            y += style.sectionGap

            // Meta (right)
            let metaX: CGFloat = pageWidth - style.margin - 240
            let metaWidth: CGFloat = 240

            if metaIncludesNumber {
                drawText(numberText,
                         font: UIFont.systemFont(ofSize: style.metaFont.pointSize, weight: .semibold),
                         rect: CGRect(x: metaX, y: y, width: metaWidth, height: 18),
                         color: style.primaryText,
                         alignment: .right)
            }

            drawText("Issue Date: \(formatDate(invoice.issueDate))",
                     font: style.metaFont,
                     rect: CGRect(x: metaX, y: y + (metaIncludesNumber ? 18 : 0), width: metaWidth, height: 18),
                     color: style.secondaryText,
                     alignment: .right)

            drawText("Due Date: \(formatDate(invoice.dueDate))",
                     font: style.metaFont,
                     rect: CGRect(x: metaX, y: y + (metaIncludesNumber ? 36 : 18), width: metaWidth, height: 18),
                     color: style.secondaryText,
                     alignment: .right)

            let now = Date()
            let overdue = (!invoice.isPaid && invoice.dueDate < now)

            let statusText: String
            let statusColor: UIColor

            if isEstimate {
                statusText = "Status: ESTIMATE"
                statusColor = style.secondaryText
            } else {
                statusColor = invoice.isPaid ? paidColor : (overdue ? overdueColor : unpaidColor)
                statusText = invoice.isPaid
                    ? "Status: PAID"
                    : (overdue ? "Status: OVERDUE" : "Status: UNPAID")
            }

            drawText(statusText,
                     font: UIFont.systemFont(ofSize: style.metaFont.pointSize, weight: .semibold),
                     rect: CGRect(x: metaX, y: y + (metaIncludesNumber ? 54 : 36), width: metaWidth, height: 18),
                     color: statusColor,
                     alignment: .right)

            // Bill To
            let clientName = invoice.client?.name ?? "Client Name"
            let clientEmail = invoice.client?.email ?? ""
            let clientPhone = invoice.client?.phone ?? ""
            let clientAddress = invoice.client?.address ?? ""

            let billTo = ["Bill To:", clientName, clientAddress, clientPhone, clientEmail]
                .filter { !trimmed($0).isEmpty }
                .joined(separator: "\n")

            drawText(billTo,
                     font: style.bodyFont,
                     rect: CGRect(x: style.margin, y: y, width: 320, height: 90),
                     color: style.primaryText)

            y += 100
            drawLine(y, alpha: style.minimalLines ? 0.8 : 1)
            y += max(10, style.sectionGap - 2)

            // Items table
            let colDesc: CGFloat = style.margin
            let tableMaxX: CGFloat = pageWidth - style.margin
            let columnGap: CGFloat = 8
            let amountWidth: CGFloat = 86
            let rateWidth: CGFloat = 78
            let qtyWidth: CGFloat = 52
            let colAmt: CGFloat = tableMaxX - amountWidth
            let colRate: CGFloat = colAmt - columnGap - rateWidth
            let colQty: CGFloat = colRate - columnGap - qtyWidth
            let descWidth = colQty - colDesc - columnGap
            let bottomMargin: CGFloat = max(48, style.margin)
            let tableBottomY = pageHeight - bottomMargin
            let tableHeaderBodyOffset = CGFloat(18) + max(8, style.rowGap + 2)
            let freshTableBodyTop = style.margin + tableHeaderBodyOffset

            func drawTableHeader() {
                drawText("Description", font: style.tableHeaderFont,
                         rect: CGRect(x: colDesc, y: y, width: descWidth, height: 16),
                         color: style.primaryText)

                drawText("Qty", font: style.tableHeaderFont,
                         rect: CGRect(x: colQty, y: y, width: qtyWidth, height: 16),
                         color: style.primaryText, alignment: .right)

                drawText("Rate", font: style.tableHeaderFont,
                         rect: CGRect(x: colRate, y: y, width: rateWidth, height: 16),
                         color: style.primaryText, alignment: .right)

                drawText("Amount", font: style.tableHeaderFont,
                         rect: CGRect(x: colAmt, y: y, width: amountWidth, height: 16),
                         color: style.primaryText, alignment: .right)

                y += 18
                drawLine(
                    y,
                    thickness: style.strongerSeparators ? 1.4 : 1,
                    alpha: style.minimalLines ? 0.65 : 1
                )
                y += max(8, style.rowGap + 2)
            }

            let rowFont = style.bodyFont
            let descParagraph = {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .left
                paragraph.lineBreakMode = .byWordWrapping
                return paragraph
            }()
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: rowFont,
                .paragraphStyle: descParagraph
            ]
            let valueLineHeight = ceil(rowFont.lineHeight)
            let minLineItemHeight = max(style.baseRowHeight, valueLineHeight)
            let maxLineItemHeightOnFreshPage = tableBottomY - freshTableBodyTop - style.rowGap

            func fittedSingleLineFont(_ font: UIFont, text: String, width: CGFloat) -> UIFont {
                let minPointSize = max(8, font.pointSize - 2)
                var pointSize = font.pointSize

                while pointSize > minPointSize {
                    let candidate = UIFont(descriptor: font.fontDescriptor, size: pointSize)
                    let textWidth = ceil((text as NSString).size(withAttributes: [.font: candidate]).width)
                    if textWidth <= width {
                        return candidate
                    }
                    pointSize -= 0.5
                }

                return UIFont(descriptor: font.fontDescriptor, size: minPointSize)
            }

            func drawSingleLineText(_ text: String,
                                    font: UIFont,
                                    rect: CGRect,
                                    color: UIColor,
                                    alignment: NSTextAlignment = .right) {
                let fittedFont = fittedSingleLineFont(font, text: text, width: rect.width)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = .byClipping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: fittedFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            func measureLineItemHeight(_ description: String) -> CGFloat {
                max(minLineItemHeight, textHeight(description, width: descWidth, attributes: descAttrs))
            }

            func drawLineItemBackground(rowIndex: Int, rowY: CGFloat, rowHeight: CGFloat) {
                guard style.zebraRows && (rowIndex % 2 == 1) else { return }
                let zebraRect = CGRect(
                    x: style.margin,
                    y: rowY - 2,
                    width: pageWidth - (style.margin * 2),
                    height: rowHeight + style.rowGap + 2
                )
                ctx.cgContext.saveGState()
                style.zebraFillColor.setFill()
                ctx.cgContext.fill(zebraRect)
                ctx.cgContext.restoreGState()
            }

            func drawLineItemRow(_ item: InvoiceRenderModel.Line,
                                 description: String,
                                 rowHeight: CGFloat,
                                 rowIndex: Int,
                                 drawValues: Bool) {
                drawLineItemBackground(rowIndex: rowIndex, rowY: y, rowHeight: rowHeight)

                drawText(description, font: rowFont,
                         rect: CGRect(x: colDesc, y: y, width: descWidth, height: rowHeight),
                         color: style.primaryText)

                guard drawValues else { return }

                let valueRectHeight = max(rowHeight, valueLineHeight)
                drawSingleLineText(String(format: "%.2f", item.quantity),
                                   font: rowFont,
                                   rect: CGRect(x: colQty, y: y, width: qtyWidth, height: valueRectHeight),
                                   color: style.secondaryText)

                drawSingleLineText(money(item.unitPrice),
                                   font: rowFont,
                                   rect: CGRect(x: colRate, y: y, width: rateWidth, height: valueRectHeight),
                                   color: style.secondaryText)

                drawSingleLineText(money(item.lineTotal),
                                   font: rowFont,
                                   rect: CGRect(x: colAmt, y: y, width: amountWidth, height: valueRectHeight),
                                   color: style.primaryText)
            }

            func addPageWithRepeatedHeaderIfNeeded() {
                ctx.beginPage()
                drawHeaderBackgroundIfNeeded()
                drawWatermarkIfNeeded()
                y = style.margin
                drawTableHeader()
            }

            func ensureSpace(_ requiredHeight: CGFloat) {
                if y + requiredHeight > tableBottomY {
                    addPageWithRepeatedHeaderIfNeeded()
                }
            }

            func trimLeadingWhitespace(_ text: String) -> String {
                let source = text as NSString
                let firstContent = source.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
                if firstContent.location == NSNotFound { return "" }
                return source.substring(from: firstContent.location)
            }

            func remainingText(after chunk: String, in text: String) -> String {
                let source = text as NSString
                let consumedLength = min((chunk as NSString).length, source.length)
                guard consumedLength < source.length else { return "" }
                return trimLeadingWhitespace(source.substring(from: consumedLength))
            }

            func drawSplitLineItemRow(_ item: InvoiceRenderModel.Line, description: String, rowIndex: Int) {
                var remaining = description
                var isFirstSegment = true

                while !remaining.isEmpty {
                    let availableTextHeight = tableBottomY - y - style.rowGap
                    if isFirstSegment &&
                        y > freshTableBodyTop &&
                        availableTextHeight < max(96, minLineItemHeight * 4) {
                        addPageWithRepeatedHeaderIfNeeded()
                        continue
                    }

                    if availableTextHeight < minLineItemHeight {
                        addPageWithRepeatedHeaderIfNeeded()
                        continue
                    }

                    let segment = largestPrefixThatFits(
                        text: remaining,
                        width: descWidth,
                        maxHeight: availableTextHeight,
                        attributes: descAttrs
                    )
                    let chunk = segment.isEmpty ? String((remaining as NSString).substring(to: 1)) : segment
                    let chunkHeight = measureLineItemHeight(chunk)

                    drawLineItemRow(item,
                                    description: chunk,
                                    rowHeight: chunkHeight,
                                    rowIndex: rowIndex,
                                    drawValues: isFirstSegment)
                    y += chunkHeight + style.rowGap

                    remaining = remainingText(after: chunk, in: remaining)
                    isFirstSegment = false
                }
            }

            drawTableHeader()

            var rowIndex = 0
            for item in (invoice.items ?? []) {
                let rawDesc = trimmed(item.itemDescription)
                let isPlaceholder = rawDesc.isEmpty && item.unitPrice == 0 && item.quantity == 1
                if isPlaceholder { continue }

                let normalized = normalizedMultilineText(rawDesc)
                let description = normalized.isEmpty ? "Item" : normalized
                let rowHeight = measureLineItemHeight(description)

                if rowHeight <= maxLineItemHeightOnFreshPage {
                    ensureSpace(rowHeight + style.rowGap)
                    drawLineItemRow(item,
                                    description: description,
                                    rowHeight: rowHeight,
                                    rowIndex: rowIndex,
                                    drawValues: true)
                    y += rowHeight + style.rowGap
                } else {
                    drawSplitLineItemRow(item, description: description, rowIndex: rowIndex)
                }

                rowIndex += 1
            }

            y += max(4, style.rowGap)
            if !style.minimalLines {
                drawLine(y, alpha: 0.95)
                y += max(10, style.sectionGap - 2)
            } else {
                y += max(8, style.sectionGap - 4)
            }

            // Totals
            let totalsRowCount = 2
                + (invoice.discountAmount > 0 ? 1 : 0)
                + (invoice.taxRate > 0 ? 1 : 0)
            let totalsRequiredHeight = CGFloat(totalsRowCount * 18) + 34
            beginNewPageIfNeeded(neededSpace: totalsRequiredHeight)

            let totalsX: CGFloat = pageWidth - style.margin - 240
            let labelWidth: CGFloat = 140
            let valueWidth: CGFloat = 100

            func totalRow(_ label: String, _ value: Double, bold: Bool = false) {
                let font = bold ? style.totalsBoldFont : style.totalsFont

                drawText(label, font: font,
                         rect: CGRect(x: totalsX, y: y, width: labelWidth, height: 16),
                         color: style.secondaryText)

                drawText(money(value), font: font,
                         rect: CGRect(x: totalsX + labelWidth, y: y, width: valueWidth, height: 16),
                         color: style.primaryText, alignment: .right)

                y += 18
            }

            totalRow("Subtotal", invoice.subtotal)
            if invoice.discountAmount > 0 { totalRow("Discount", -invoice.discountAmount) }
            if invoice.taxRate > 0 { totalRow("Tax", invoice.taxAmount) }

            y += 4
            drawLine(
                y,
                thickness: style.strongerSeparators ? 1.35 : 1,
                alpha: style.minimalLines ? 0.75 : 1
            )
            y += 10
            totalRow("Total", invoice.total, bold: true)

            y += 20

            // Footer blocks — ONLY draw if user provided content
            let paymentTermsText = trimmed(invoice.paymentTerms)
            let notesText = trimmed(invoice.notes)
            let thankYouText = trimmed(invoice.thankYou)
            let termsText = trimmed(invoice.termsAndConditions)

            let blocks: [(title: String, text: String, height: CGFloat)] = [
                ("Payment Terms", paymentTermsText, 44),
                ("Notes", notesText, 44),
                ("Thank You", thankYouText, 36),
                ("Terms & Conditions", termsText, 80)
            ]
            .filter { !trimmed($0.text).isEmpty }

            if !blocks.isEmpty {
                beginNewPageIfNeeded(neededSpace: 60 + CGFloat(blocks.count) * 70)

                let footerTitleFont = UIFont.systemFont(ofSize: style.metaFont.pointSize, weight: .semibold)
                let footerTextWidth = pageWidth - (style.margin * 2)
                let footerParagraph = NSMutableParagraphStyle()
                footerParagraph.alignment = .left
                footerParagraph.lineBreakMode = .byWordWrapping
                footerParagraph.lineSpacing = 2.5
                footerParagraph.paragraphSpacing = 6
                let footerTextAttrs: [NSAttributedString.Key: Any] = [
                    .font: style.bodyFont,
                    .foregroundColor: style.secondaryText,
                    .paragraphStyle: footerParagraph
                ]

                func drawFooterBlock(_ title: String, _ text: String, minHeight: CGFloat) {
                    var remaining = normalizedMultilineText(text)
                    var isContinuation = false

                    while true {
                        beginNewPageIfNeeded(neededSpace: 34)

                        let headerTitle = isContinuation ? "\(title) (continued)" : title
                        drawText(headerTitle,
                                 font: footerTitleFont,
                                 rect: CGRect(x: style.margin, y: y, width: footerTextWidth, height: 16),
                                 color: style.primaryText)
                        y += 18

                        let bottomMargin: CGFloat = max(48, style.margin)
                        let maxTextHeight = pageHeight - bottomMargin - y
                        if maxTextHeight <= 20 {
                            ctx.beginPage()
                            drawHeaderBackgroundIfNeeded()
                            y = style.margin
                            continue
                        }

                        let segment = largestPrefixThatFits(
                            text: remaining,
                            width: footerTextWidth,
                            maxHeight: maxTextHeight,
                            attributes: footerTextAttrs
                        )
                        let chunk = segment.isEmpty ? String((remaining as NSString).substring(to: 1)) : segment
                        let chunkHeight = max(minHeight, textHeight(chunk, width: footerTextWidth, attributes: footerTextAttrs))

                        drawAttributedText(
                            chunk,
                            rect: CGRect(x: style.margin, y: y, width: footerTextWidth, height: chunkHeight),
                            attributes: footerTextAttrs
                        )
                        y += chunkHeight + 12

                        let consumedLength = (chunk as NSString).length
                        if consumedLength >= (remaining as NSString).length {
                            break
                        }

                        remaining = (remaining as NSString).substring(from: consumedLength)
                        isContinuation = true
                        beginNewPageIfNeeded(neededSpace: 26)
                    }
                }

                for block in blocks {
                    drawFooterBlock(block.title, block.text, minHeight: block.height)
                }
            }
        }

        return data
    }

    static func writePDFToTemporaryFile(data: Data, filename: String) throws -> URL {
        let safe = sanitizedPDFBaseName(filename)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
