//
//  ContractPDFGenerator.swift
//  SmallBiz Workspace
//

import Foundation
import UIKit

enum ContractPDFGenerator {

    static func makePDFData(contract: Contract, business: BusinessProfile?) -> Data {

        // US Letter 8.5" x 11" @ 72 dpi
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        // Layout constants
        let marginX: CGFloat = 40
        let topMargin: CGFloat = 40
        let bottomMargin: CGFloat = 48
        let contentWidth: CGFloat = pageWidth - (marginX * 2)

        // PDF-safe (non-dynamic) colors for consistent output on-device
        let primaryText = UIColor.black
        let secondaryText = UIColor.darkGray
        let lineColor = UIColor(white: 0.85, alpha: 1.0)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            var y = topMargin

            func beginPage() {
                ctx.beginPage()
                y = topMargin
            }

            func drawLine(_ lineY: CGFloat, thickness: CGFloat = 1) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: marginX, y: lineY))
                path.addLine(to: CGPoint(x: pageWidth - marginX, y: lineY))
                lineColor.setStroke()
                path.lineWidth = thickness
                path.stroke()
            }

            func drawText(
                _ text: String,
                font: UIFont,
                rect: CGRect,
                color: UIColor = UIColor.black,
                alignment: NSTextAlignment = .left,
                lineBreak: NSLineBreakMode = .byWordWrapping
            ) {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = lineBreak

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style
                ]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            func attributedHeight(text: String, font: UIFont, width: CGFloat) -> CGFloat {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                style.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: style
                ]

                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                return ceil(bounding.height)
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > (pageHeight - bottomMargin) {
                    beginPage()
                }
            }

            func formatDate(_ d: Date) -> String {
                let df = DateFormatter()
                df.dateStyle = .medium
                return df.string(from: d)
            }

            // Draws long body text with real pagination
            func drawPagedBody(_ text: String, font: UIFont) {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                style.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: primaryText,
                    .paragraphStyle: style
                ]

                // Treat blank lines as paragraph breaks
                let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

                let lineGap: CGFloat = 6

                for p in paragraphs {
                    let paragraphText = p.isEmpty ? " " : p
                    let height = attributedHeight(text: paragraphText, font: font, width: contentWidth)

                    ensureSpace(height + lineGap)

                    let rect = CGRect(x: marginX, y: y, width: contentWidth, height: height)
                    (paragraphText as NSString).draw(in: rect, withAttributes: attrs)

                    y += height + lineGap
                }
            }

            // Signature blocks at bottom (or next page)
            func drawSignatureBlocks() {
                let blockHeight: CGFloat = 120
                ensureSpace(blockHeight)

                drawLine(y, thickness: 1)
                y += 18

                let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
                let textFont = UIFont.systemFont(ofSize: 10.5, weight: .regular)

                let leftX = marginX
                let rightX = marginX + (contentWidth / 2) + 10
                let colWidth = (contentWidth / 2) - 10

                drawText("Client Signature", font: labelFont,
                         rect: CGRect(x: leftX, y: y, width: colWidth, height: 14),
                         color: secondaryText)

                drawText("Business Signature", font: labelFont,
                         rect: CGRect(x: rightX, y: y, width: colWidth, height: 14),
                         color: secondaryText)

                y += 18

                // Signature lines
                drawLine(y + 22, thickness: 1)
                drawLine(y + 22, thickness: 1) // left line is same function but spans full width; we’ll draw custom below

                // Custom short lines
                func shortLine(x: CGFloat, y: CGFloat, w: CGFloat) {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + w, y: y))
                    lineColor.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }

                shortLine(x: leftX, y: y + 22, w: colWidth)
                shortLine(x: rightX, y: y + 22, w: colWidth)

                // Date lines
                shortLine(x: leftX, y: y + 64, w: colWidth * 0.4)
                shortLine(x: rightX, y: y + 64, w: colWidth * 0.4)

                drawText("Date", font: textFont,
                         rect: CGRect(x: leftX, y: y + 68, width: colWidth * 0.4, height: 14),
                         color: secondaryText)

                drawText("Date", font: textFont,
                         rect: CGRect(x: rightX, y: y + 68, width: colWidth * 0.4, height: 14),
                         color: secondaryText)

                // Optional business name under business signature
                let bizName = (business?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !bizName.isEmpty {
                    drawText(bizName, font: textFont,
                             rect: CGRect(x: rightX, y: y + 28, width: colWidth, height: 14),
                             color: secondaryText)
                }

                y += blockHeight - 18
            }

            // MARK: - Start
            beginPage()

            // MARK: - Header (logo + business + contract title)
            let hasLogo = (business?.logoData != nil)

            if let logoData = business?.logoData,
               let logoImage = UIImage(data: logoData) {

                let maxLogoHeight: CGFloat = 52
                let maxLogoWidth: CGFloat = 170

                let imgAspect = logoImage.size.width / logoImage.size.height
                var w = imgAspect * maxLogoHeight
                var h = maxLogoHeight

                if w > maxLogoWidth {
                    w = maxLogoWidth
                    h = w / imgAspect
                }

                let rect = CGRect(x: marginX, y: y, width: w, height: h)
                logoImage.draw(in: rect)
            }

            drawText(
                "CONTRACT",
                font: .systemFont(ofSize: 22, weight: .bold),
                rect: CGRect(x: marginX, y: y, width: contentWidth, height: 26),
                color: primaryText,
                alignment: .right
            )

            // Business block (push right if logo present)
            let bizName = (business?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bizEmail = (business?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bizPhone = (business?.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bizAddress = (business?.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let businessLines = [
                bizName.isEmpty ? nil : bizName,
                bizAddress.isEmpty ? nil : bizAddress,
                bizPhone.isEmpty ? nil : bizPhone,
                bizEmail.isEmpty ? nil : bizEmail
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            let businessX: CGFloat = hasLogo ? marginX + 190 : marginX

            if !businessLines.isEmpty {
                drawText(
                    businessLines,
                    font: .systemFont(ofSize: 10.5, weight: .regular),
                    rect: CGRect(x: businessX, y: y, width: 340, height: 70),
                    color: secondaryText,
                    alignment: .left
                )
            }

            y += hasLogo ? 80 : 70
            drawLine(y)
            y += 14

            let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Contract"
                : contract.title.trimmingCharacters(in: .whitespacesAndNewlines)

            drawText(title,
                     font: .systemFont(ofSize: 16, weight: .semibold),
                     rect: CGRect(x: marginX, y: y, width: contentWidth, height: 20),
                     color: primaryText)

            y += 24

            let statusDisplay = ContractStatus(rawValue: contract.statusRaw)?.rawValue.capitalized ?? "Draft"
            let meta = "Status: \(statusDisplay)    •    Updated: \(formatDate(contract.updatedAt))"
            drawText(meta,
                     font: .systemFont(ofSize: 10.5, weight: .regular),
                     rect: CGRect(x: marginX, y: y, width: contentWidth, height: 14),
                     color: secondaryText)

            y += 18
            drawLine(y)
            y += 16

            // MARK: - Body (paged)
            let body = contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            drawPagedBody(body.isEmpty ? " " : body, font: .systemFont(ofSize: 11.5, weight: .regular))

            // MARK: - Signature blocks
            drawSignatureBlocks()

            // Footer
            ensureSpace(30)
            let footerY = min(y + 8, pageHeight - 30)
            drawText("Generated by SmallBiz Workspace",
                     font: .systemFont(ofSize: 9.5, weight: .regular),
                     rect: CGRect(x: marginX, y: footerY, width: contentWidth, height: 14),
                     color: secondaryText,
                     alignment: .center)
        }
    }

    static func writePDFToTemporaryFile(data: Data, filename: String) throws -> URL {
        let safe = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
