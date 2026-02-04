import Foundation
import UIKit

enum InvoicePDFGenerator {

    static func makePDFData(invoice: Invoice, business: BusinessSnapshot) -> Data {

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let isEstimate = (invoice.documentType == "estimate")
        let docTitle = isEstimate ? "ESTIMATE" : "INVOICE"

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let primaryText = UIColor.black
        let secondaryText = UIColor.darkGray
        let lineColor = UIColor(white: 0.85, alpha: 1.0)

        let paidColor = UIColor(red: 0.10, green: 0.60, blue: 0.25, alpha: 1.0)
        let unpaidColor = UIColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1.0)
        let overdueColor = UIColor(red: 0.75, green: 0.10, blue: 0.10, alpha: 1.0)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 36

            func drawText(_ text: String,
                          font: UIFont,
                          rect: CGRect,
                          color: UIColor = UIColor.black,
                          alignment: NSTextAlignment = .left,
                          lineBreak: NSLineBreakMode = .byWordWrapping) {
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

            func drawLine(_ lineY: CGFloat, thickness: CGFloat = 1) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 36, y: lineY))
                path.addLine(to: CGPoint(x: pageWidth - 36, y: lineY))
                lineColor.setStroke()
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
                let bottomMargin: CGFloat = 48
                if y + neededSpace > pageHeight - bottomMargin {
                    ctx.beginPage()
                    y = 36
                }
            }

            func trimmed(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // ✅ Optional change #1:
            // Watermark rules:
            // - Estimates: light "ESTIMATE"
            // - Invoices: PAID / OVERDUE (same as before)
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

            if let logoData = business.logoData,
               let logoImage = UIImage(data: logoData) {

                let maxLogoHeight: CGFloat = 60
                let maxLogoWidth: CGFloat = 170
                let imgAspect = logoImage.size.width / logoImage.size.height
                var width = imgAspect * maxLogoHeight
                var height = maxLogoHeight

                if width > maxLogoWidth {
                    width = maxLogoWidth
                    height = width / imgAspect
                }

                logoImage.draw(in: CGRect(x: 36, y: y, width: width, height: height))
            }

            drawText(docTitle,
                     font: .systemFont(ofSize: 28, weight: .bold),
                     rect: CGRect(x: 36, y: y, width: pageWidth - 72, height: 34),
                     color: primaryText,
                     alignment: .right)

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

            let businessX: CGFloat = hasLogo ? 36 + 190 : 36
            drawText(businessLines,
                     font: .systemFont(ofSize: 12, weight: .regular),
                     rect: CGRect(x: businessX, y: y, width: 320, height: 90),
                     color: primaryText)

            y += hasLogo ? 106 : 96
            drawLine(y, thickness: 1)
            y += 16

            // Meta (right)
            let metaX: CGFloat = pageWidth - 36 - 240
            let metaWidth: CGFloat = 240

            // ✅ Fix: Invoice # label switches to Estimate #
            let numberLabel = isEstimate ? "Estimate #:" : "Invoice #:"
            drawText("\(numberLabel) \(invoice.invoiceNumber)",
                     font: .systemFont(ofSize: 12, weight: .semibold),
                     rect: CGRect(x: metaX, y: y, width: metaWidth, height: 18),
                     color: primaryText,
                     alignment: .right)

            drawText("Issue Date: \(formatDate(invoice.issueDate))",
                     font: .systemFont(ofSize: 12, weight: .regular),
                     rect: CGRect(x: metaX, y: y + 18, width: metaWidth, height: 18),
                     color: secondaryText,
                     alignment: .right)

            drawText("Due Date: \(formatDate(invoice.dueDate))",
                     font: .systemFont(ofSize: 12, weight: .regular),
                     rect: CGRect(x: metaX, y: y + 36, width: metaWidth, height: 18),
                     color: secondaryText,
                     alignment: .right)

            // ✅ Optional change #2: Status line rules
            let now = Date()
            let overdue = (!invoice.isPaid && invoice.dueDate < now)

            let statusText: String
            let statusColor: UIColor

            if isEstimate {
                statusText = "Status: ESTIMATE"
                statusColor = secondaryText
            } else {
                statusColor = invoice.isPaid ? paidColor : (overdue ? overdueColor : unpaidColor)
                statusText = invoice.isPaid
                    ? "Status: PAID"
                    : (overdue ? "Status: OVERDUE" : "Status: UNPAID")
            }

            drawText(statusText,
                     font: .systemFont(ofSize: 12, weight: .semibold),
                     rect: CGRect(x: metaX, y: y + 54, width: metaWidth, height: 18),
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
                     font: .systemFont(ofSize: 12, weight: .regular),
                     rect: CGRect(x: 36, y: y, width: 320, height: 90),
                     color: primaryText)

            y += 100
            drawLine(y)
            y += 14

            // Items table
            let colDesc: CGFloat = 36
            let colQty: CGFloat = 380
            let colRate: CGFloat = 450
            let colAmt: CGFloat = 530

            func drawTableHeader() {
                drawText("Description", font: .systemFont(ofSize: 11, weight: .semibold),
                         rect: CGRect(x: colDesc, y: y, width: colQty - colDesc - 8, height: 16),
                         color: primaryText)

                drawText("Qty", font: .systemFont(ofSize: 11, weight: .semibold),
                         rect: CGRect(x: colQty, y: y, width: 60, height: 16),
                         color: primaryText, alignment: .right)

                drawText("Rate", font: .systemFont(ofSize: 11, weight: .semibold),
                         rect: CGRect(x: colRate, y: y, width: 70, height: 16),
                         color: primaryText, alignment: .right)

                drawText("Amount", font: .systemFont(ofSize: 11, weight: .semibold),
                         rect: CGRect(x: colAmt, y: y, width: 46, height: 16),
                         color: primaryText, alignment: .right)

                y += 18
                drawLine(y)
                y += 10
            }

            drawTableHeader()

            let rowFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let rowHeight: CGFloat = 18

            for item in (invoice.items ?? []) {

                if y > pageHeight - 210 {
                    ctx.beginPage()
                    y = 36
                    drawWatermarkIfNeeded()
                    drawTableHeader()
                }

                let desc = trimmed(item.itemDescription).isEmpty ? "Item" : item.itemDescription

                drawText(desc, font: rowFont,
                         rect: CGRect(x: colDesc, y: y, width: colQty - colDesc - 8, height: rowHeight),
                         color: primaryText)

                drawText(String(format: "%.2f", item.quantity), font: rowFont,
                         rect: CGRect(x: colQty, y: y, width: 60, height: rowHeight),
                         color: secondaryText, alignment: .right)

                drawText(money(item.unitPrice), font: rowFont,
                         rect: CGRect(x: colRate, y: y, width: 70, height: rowHeight),
                         color: secondaryText, alignment: .right)

                drawText(money(item.lineTotal), font: rowFont,
                         rect: CGRect(x: colAmt, y: y, width: 46, height: rowHeight),
                         color: primaryText, alignment: .right)

                y += rowHeight + 6
            }

            y += 6
            drawLine(y)
            y += 14

            // Totals
            let totalsX: CGFloat = pageWidth - 36 - 240
            let labelWidth: CGFloat = 140
            let valueWidth: CGFloat = 100

            func totalRow(_ label: String, _ value: Double, bold: Bool = false) {
                let f = bold
                    ? UIFont.systemFont(ofSize: 12, weight: .bold)
                    : UIFont.systemFont(ofSize: 12, weight: .regular)

                drawText(label, font: f,
                         rect: CGRect(x: totalsX, y: y, width: labelWidth, height: 16),
                         color: secondaryText)

                drawText(money(value), font: f,
                         rect: CGRect(x: totalsX + labelWidth, y: y, width: valueWidth, height: 16),
                         color: primaryText, alignment: .right)

                y += 18
            }

            totalRow("Subtotal", invoice.subtotal)
            if invoice.discountAmount > 0 { totalRow("Discount", -invoice.discountAmount) }
            if invoice.taxRate > 0 { totalRow("Tax", invoice.taxAmount) }

            y += 4
            drawLine(y)
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

                func titledBlock(_ title: String, _ text: String, height: CGFloat) {
                    drawText(title,
                             font: .systemFont(ofSize: 12, weight: .semibold),
                             rect: CGRect(x: 36, y: y, width: pageWidth - 72, height: 16),
                             color: primaryText)
                    y += 18

                    drawText(text,
                             font: .systemFont(ofSize: 11, weight: .regular),
                             rect: CGRect(x: 36, y: y, width: pageWidth - 72, height: height),
                             color: secondaryText)
                    y += height + 12
                }

                for b in blocks {
                    titledBlock(b.title, b.text, height: b.height)
                }
            }
        }

        return data
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
