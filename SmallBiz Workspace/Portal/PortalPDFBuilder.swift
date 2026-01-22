//
//  PortalPDFBuilder.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/19/26.
//

import Foundation
import UIKit

enum PortalPDFBuilder {

    static func buildInvoicePDF(invoice: Invoice, business: BusinessProfile?) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let fileName = "\(invoice.documentType.uppercased())-\(invoice.invoiceNumber).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            var y: CGFloat = 36
            let left: CGFloat = 36
            let right: CGFloat = pageRect.width - 36

            func draw(_ text: String, font: UIFont, color: UIColor = .black) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let s = NSAttributedString(string: text, attributes: attrs)
                let size = s.boundingRect(
                    with: CGSize(width: right - left, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).size
                s.draw(in: CGRect(x: left, y: y, width: right - left, height: size.height))
                y += size.height + 6
            }

            func drawTwoColumn(leftText: String, rightText: String) {
                let leftRect = CGRect(x: left, y: y, width: (right - left) * 0.6, height: 1000)
                let rightRect = CGRect(x: left + (right - left) * 0.6, y: y, width: (right - left) * 0.4, height: 1000)

                let leftAttr = NSAttributedString(string: leftText, attributes: [.font: UIFont.systemFont(ofSize: 12)])
                let rightAttr = NSAttributedString(string: rightText, attributes: [.font: UIFont.systemFont(ofSize: 12)])

                let leftSize = leftAttr.boundingRect(with: CGSize(width: leftRect.width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
                let rightSize = rightAttr.boundingRect(with: CGSize(width: rightRect.width, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size

                leftAttr.draw(in: CGRect(x: leftRect.minX, y: y, width: leftRect.width, height: leftSize.height))
                rightAttr.draw(in: CGRect(x: rightRect.minX, y: y, width: rightRect.width, height: rightSize.height))

                y += max(leftSize.height, rightSize.height) + 10
            }

            // Header
            let docTitle = invoice.documentType.lowercased() == "estimate" ? "ESTIMATE" : "INVOICE"
            draw(docTitle, font: .boldSystemFont(ofSize: 26))

            if let biz = business {
                draw(biz.name, font: .boldSystemFont(ofSize: 14))
                draw([biz.email, biz.phone].filter { !$0.isEmpty }.joined(separator: " • "), font: .systemFont(ofSize: 12), color: .darkGray)
                if !biz.address.isEmpty { draw(biz.address, font: .systemFont(ofSize: 12), color: .darkGray) }
            }

            y += 6
            UIGraphicsGetCurrentContext()?.setStrokeColor(UIColor.lightGray.cgColor)
            UIGraphicsGetCurrentContext()?.setLineWidth(1)
            UIGraphicsGetCurrentContext()?.move(to: CGPoint(x: left, y: y))
            UIGraphicsGetCurrentContext()?.addLine(to: CGPoint(x: right, y: y))
            UIGraphicsGetCurrentContext()?.strokePath()
            y += 14

            // Client + meta
            let client = invoice.client
            let clientBlock = """
            Bill To:
            \(client?.name ?? "")
            \(client?.email ?? "")
            \(client?.phone ?? "")
            \(client?.address ?? "")
            """.trimmingCharacters(in: .whitespacesAndNewlines)

            let metaBlock = """
            # \(invoice.invoiceNumber)
            Issued: \(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
            Due: \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
            Terms: \(invoice.paymentTerms)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

            drawTwoColumn(leftText: clientBlock, rightText: metaBlock)

            // Items
            draw("Items", font: .boldSystemFont(ofSize: 14))
            let items = invoice.items ?? []
            if items.isEmpty {
                draw("No items", font: .systemFont(ofSize: 12), color: .darkGray)
            } else {
                for it in items {
                    let line = "• \(it.itemDescription)  —  \(formatQty(it.quantity)) × \(formatMoney(it.unitPrice))  =  \(formatMoney(it.lineTotal))"
                    draw(line, font: .systemFont(ofSize: 12))
                    if y > pageRect.height - 120 {
                        ctx.beginPage()
                        y = 36
                    }
                }
            }

            y += 8

            // Totals (your model computes subtotal/tax/total):contentReference[oaicite:2]{index=2}
            draw("Subtotal: \(formatMoney(invoice.subtotal))", font: .systemFont(ofSize: 12))
            if invoice.discountAmount > 0 {
                draw("Discount: -\(formatMoney(invoice.discountAmount))", font: .systemFont(ofSize: 12))
            }
            if invoice.taxRate > 0 {
                draw("Tax: \(formatMoney(invoice.taxAmount))", font: .systemFont(ofSize: 12))
            }
            draw("Total: \(formatMoney(invoice.total))", font: .boldSystemFont(ofSize: 14))

            y += 10

            if !invoice.notes.isEmpty {
                draw("Notes", font: .boldSystemFont(ofSize: 13))
                draw(invoice.notes, font: .systemFont(ofSize: 12))
            }

            if !invoice.termsAndConditions.isEmpty {
                draw("Terms & Conditions", font: .boldSystemFont(ofSize: 13))
                draw(invoice.termsAndConditions, font: .systemFont(ofSize: 12))
            }

            if !invoice.thankYou.isEmpty {
                draw(invoice.thankYou, font: .italicSystemFont(ofSize: 12), color: .darkGray)
            }
        }

        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private static func formatQty(_ v: Double) -> String {
        if v.rounded(.towardZero) == v { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}
