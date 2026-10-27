//
//  ContractPDFGenerator.swift
//  SmallBiz Workspace
//

import Foundation
import UIKit

/// The contract PDF the client reads and signs in the portal.
///
/// Laid out like the founder's production agreement: a running header, the
/// body's titles, headings, numbered clauses and tables (`ContractDocument`),
/// a signature page, and "Client Initials / Provider Initials / Page X of Y"
/// on every page. A body with none of that markup prints as paragraphs with
/// the signatures at the end, as contracts always have.
enum ContractPDFGenerator {

    struct Input {
        var title: String
        var body: String
        var preparedDate: Date
        var business: BusinessProfile?
        var client: ClientSnapshot?
        var clientSignature: (name: String, method: String, date: String)?
    }

    static func makePDFData(contract: Contract, business: BusinessProfile?) -> Data {
        makePDFData(Input(
            title: contract.title,
            body: contract.renderedBody,
            preparedDate: contract.sentAt ?? contract.updatedAt,
            business: business,
            client: contract.clientForRendering,
            clientSignature: clientSignature(for: contract)
        ))
    }

    static func makePDFData(_ input: Input) -> Data {
        // Drawn twice: once to count the pages for "Page X of Y".
        var layout = Layout(input: input, totalPages: nil)
        _ = layout.render()
        var final = Layout(input: input, totalPages: layout.pageCount)
        return final.render()
    }

    /// The client's side of the signature block, or nil until signed.
    static func clientSignature(for contract: Contract) -> (name: String, method: String, date: String)? {
        guard contract.status == .signed else { return nil }
        let name = contract.signedByName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let method = contract.signedMethod == "in_person" ? "Signed in person" : "Signed electronically"
        let date = contract.signedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        return (name, method, date)
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

// MARK: - Layout

private struct Layout {
    let input: ContractPDFGenerator.Input
    let totalPages: Int?

    // US Letter at 72 dpi
    let pageWidth: CGFloat = 612
    let pageHeight: CGFloat = 792
    let marginX: CGFloat = 48
    let contentTop: CGFloat = 62
    var contentBottom: CGFloat { pageHeight - 64 }
    var contentWidth: CGFloat { pageWidth - marginX * 2 }
    let gutter: CGFloat = 32

    // PDF-safe (non-dynamic) colors
    let ink = UIColor.black
    let muted = UIColor(white: 0.36, alpha: 1)
    let rule = UIColor(white: 0.80, alpha: 1)
    let shade = UIColor(white: 0.95, alpha: 1)
    let accent: UIColor
    let accentShade: UIColor

    let structured: Bool
    let businessName: String

    private(set) var pageCount = 0
    private var y: CGFloat = 0
    private var context: UIGraphicsPDFRendererContext?

    init(input: ContractPDFGenerator.Input, totalPages: Int?) {
        self.input = input
        self.totalPages = totalPages
        let hex = BrandColor.readableOnWhite(BrandColor.resolved(input.business?.brandColorHex))
        accent = BrandColor.uiColor(hex)
        accentShade = BrandColor.uiColor(BrandColor.tint(hex, amount: 0.10))
        structured = ContractDocument.isStructured(input.body)
        businessName = (input.business?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        let t = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Contract" : t
    }

    private var clientName: String {
        (input.client?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func render() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        pageCount = 0
        var copy = self
        let data = renderer.pdfData { ctx in
            copy.context = ctx
            copy.drawDocument()
        }
        pageCount = copy.pageCount
        return data
    }

    // MARK: Document

    private mutating func drawDocument() {
        beginPage()
        drawLetterhead()

        let blocks = ContractDocument.parse(input.body.trimmingCharacters(in: .whitespacesAndNewlines))
        if !blocks.contains(where: { if case .title = $0 { return true }; return false }) {
            // An older body has no title line of its own.
            drawTitle(title)
            draw(
                "Prepared \(input.preparedDate.formatted(date: .abbreviated, time: .omitted))",
                font: .systemFont(ofSize: 9.5), color: muted, x: marginX, width: contentWidth, alignment: .center
            )
            y += 10
        }

        var drewSignatures = false
        var previous: ContractBlock?
        for block in blocks {
            switch block {
            case .title(let text): drawTitle(text)
            case .subtitle(let text):
                draw(text, font: .italicSystemFont(ofSize: 10), color: muted, x: marginX, width: contentWidth, alignment: .center)
                y += 10
            case .heading(let text): drawHeading(text)
            case let .clause(number, lead, text): drawClause(number: number, lead: lead, text: text)
            case let .item(marker, text): drawItem(marker: marker, text: text)
            case let .table(header, rows): drawTable(header: header, rows: rows)
            case .paragraph(let text):
                draw(text, font: .systemFont(ofSize: 10.5), color: ink, x: marginX, width: contentWidth, keep: 14)
                y += 5
            case .gap:
                if case .some(.gap) = previous {} else { y += 4 }
            case .pageBreak:
                if y > contentTop + 1 { beginPage() }
            case .signatures:
                drawSignatures()
                drewSignatures = true
            }
            previous = block
        }

        if !drewSignatures {
            y += 10
            drawSignatures()
        }
    }

    // MARK: Pages

    private mutating func beginPage() {
        context?.beginPage()
        pageCount += 1
        y = contentTop
        drawRunningHeader()
        drawFooter()
    }

    private mutating func ensureSpace(_ needed: CGFloat) {
        if y + needed > contentBottom { beginPage() }
    }

    private var isLastPage: Bool { totalPages.map { pageCount == $0 } ?? false }

    private func drawRunningHeader() {
        let headerY: CGFloat = 30
        let left = businessName.uppercased()
        let right = clientName.isEmpty ? title : "\(title) — \(clientName)"
        let leftWidth = contentWidth * 0.42
        drawFixed(left, font: .systemFont(ofSize: 8, weight: .bold), color: accent,
                  rect: CGRect(x: marginX, y: headerY, width: leftWidth, height: 12), kern: 0.8)
        drawFixed(right, font: .systemFont(ofSize: 8), color: muted,
                  rect: CGRect(x: marginX + leftWidth, y: headerY, width: contentWidth - leftWidth, height: 12),
                  alignment: .right)
        line(y: headerY + 15, color: rule, width: 0.75)
    }

    private func drawFooter() {
        let footerY = pageHeight - 44
        line(y: footerY - 6, color: rule, width: 0.75)
        let font = UIFont.systemFont(ofSize: 8.5)
        if structured {
            drawFixed("Client Initials ______     Provider Initials ______", font: font, color: muted,
                      rect: CGRect(x: marginX, y: footerY, width: contentWidth * 0.6, height: 12))
        }
        if let totalPages {
            drawFixed("Page \(pageCount) of \(totalPages)", font: font, color: muted,
                      rect: CGRect(x: marginX, y: footerY, width: contentWidth, height: 12), alignment: .right)
        }
        if isLastPage {
            drawFixed("Powered by SmallBiz Workspace", font: .systemFont(ofSize: 7.5), color: muted,
                      rect: CGRect(x: marginX, y: footerY + 14, width: contentWidth, height: 10), alignment: .center)
        }
    }

    // MARK: Blocks

    /// Logo and contact details at the top of the first page.
    private mutating func drawLetterhead() {
        let lines = [
            businessName,
            input.business?.address ?? "",
            input.business?.phone ?? "",
            input.business?.email ?? ""
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        var height: CGFloat = 0
        if let data = input.business?.logoData, let logo = UIImage(data: data), logo.size.height > 0 {
            let maxH: CGFloat = 46, maxW: CGFloat = 160
            var w = logo.size.width / logo.size.height * maxH
            var h = maxH
            if w > maxW { w = maxW; h = w * logo.size.height / logo.size.width }
            logo.draw(in: CGRect(x: marginX, y: y, width: w, height: h))
            height = h
        }
        if !lines.isEmpty {
            let text = lines.joined(separator: "\n")
            let h = measure(text, font: .systemFont(ofSize: 9), width: 240)
            drawFixed(text, font: .systemFont(ofSize: 9), color: muted,
                      rect: CGRect(x: pageWidth - marginX - 240, y: y, width: 240, height: h), alignment: .right)
            height = max(height, h)
        }
        if height > 0 { y += height + 16 }
    }

    private mutating func drawTitle(_ text: String) {
        ensureSpace(60)
        draw(text, font: .systemFont(ofSize: 16, weight: .bold), color: ink, x: marginX, width: contentWidth,
             alignment: .center, kern: 0.6)
        y += 4
    }

    private mutating func drawHeading(_ text: String) {
        // Kept with at least a couple of lines of what follows.
        ensureSpace(54)
        y += 8
        draw(text.uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: accent, x: marginX,
             width: contentWidth, kern: 0.5)
        line(y: y + 2, color: accent.withAlphaComponent(0.35), width: 0.75)
        y += 8
    }

    private mutating func drawClause(number: String, lead: String?, text: String) {
        let body = NSMutableAttributedString()
        let font = UIFont.systemFont(ofSize: 10.5)
        if let lead {
            body.append(NSAttributedString(string: lead, attributes: [.font: UIFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: ink]))
            if !text.isEmpty { body.append(NSAttributedString(string: " ", attributes: [.font: font])) }
        }
        body.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink]))

        let width = contentWidth - gutter
        let h = measure(body, width: width)
        ensureSpace(min(h, 28))
        drawFixed(number, font: .systemFont(ofSize: 10.5, weight: .semibold), color: accent,
                  rect: CGRect(x: marginX, y: y, width: gutter, height: 14))
        drawFlowing(body, x: marginX + gutter, width: width)
        y += 5
    }

    private mutating func drawItem(marker: String, text: String) {
        let x = marginX + gutter
        let markerWidth: CGFloat = 20
        let font = UIFont.systemFont(ofSize: 10.5)
        let h = measure(text, font: font, width: contentWidth - gutter - markerWidth)
        ensureSpace(min(h, 28))
        drawFixed(marker, font: font, color: ink, rect: CGRect(x: x, y: y, width: markerWidth, height: 14))
        draw(text, font: font, color: ink, x: x + markerWidth, width: contentWidth - gutter - markerWidth)
        y += 3
    }

    private mutating func drawTable(header: [String]?, rows: [[String]]) {
        let columns = max(header?.count ?? 0, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return }
        let fractions: [CGFloat]
        switch columns {
        case 1: fractions = [1]
        case 2: fractions = [0.28, 0.72]
        case 3: fractions = [0.36, 0.34, 0.30]
        default: fractions = Array(repeating: 1 / CGFloat(columns), count: columns)
        }
        let widths = fractions.map { $0 * contentWidth }
        let pad: CGFloat = 5
        let font = UIFont.systemFont(ofSize: 9.5)
        let bold = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        // A key/value table (no header) reads its first column as labels.
        let labelColumn = header == nil && columns == 2

        func rowHeight(_ cells: [String], isHeader: Bool) -> CGFloat {
            var h: CGFloat = 0
            for (i, cell) in cells.enumerated() where i < columns {
                let f = isHeader || (labelColumn && i == 0) ? bold : font
                h = max(h, measure(cell, font: f, width: widths[i] - pad * 2))
            }
            return max(h, 12) + pad * 2 + 2
        }

        func drawRow(_ cells: [String], isHeader: Bool) {
            let h = rowHeight(cells, isHeader: isHeader)
            var x = marginX
            for i in 0..<columns {
                let rect = CGRect(x: x, y: y, width: widths[i], height: h)
                let fill: UIColor? = isHeader ? accentShade : (labelColumn && i == 0 ? shade : nil)
                if let fill { fill.setFill(); UIRectFill(rect) }
                rule.setStroke()
                let border = UIBezierPath(rect: rect)
                border.lineWidth = 0.5
                border.stroke()
                let cell = i < cells.count ? cells[i] : ""
                let f = isHeader || (labelColumn && i == 0) ? bold : font
                drawFixed(cell, font: f, color: ink,
                          rect: rect.insetBy(dx: pad, dy: pad).offsetBy(dx: 0, dy: 1))
                x += widths[i]
            }
            y += h
        }

        y += 2
        if let header {
            ensureSpace(rowHeight(header, isHeader: true) + rowHeight(rows.first ?? [], isHeader: false))
            drawRow(header, isHeader: true)
        }
        for row in rows {
            let h = rowHeight(row, isHeader: false)
            if y + h > contentBottom {
                beginPage()
                if let header { drawRow(header, isHeader: true) }
            }
            drawRow(row, isHeader: false)
        }
        y += 10
    }

    /// Provider on the left, Client on the right, each with signature,
    /// printed name / title, date, and email / phone lines.
    private mutating func drawSignatures() {
        ensureSpace(200)
        y += 10
        let colGap: CGFloat = 28
        let colWidth = (contentWidth - colGap) / 2
        let leftX = marginX
        let rightX = marginX + colWidth + colGap
        let top = y

        let providerContact = [input.business?.email, input.business?.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let clientContact = [input.client?.email, input.client?.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let signed = input.clientSignature

        func column(x: CGFloat, role: String, party: String, signature: String?, signatureNote: String?,
                    printedName: String?, date: String?, contact: String) {
            var cy = top
            drawFixed(role, font: .systemFont(ofSize: 8.5, weight: .bold), color: accent,
                      rect: CGRect(x: x, y: cy, width: colWidth, height: 12), kern: 0.8)
            cy += 13
            drawFixed(party.isEmpty ? " " : party, font: .systemFont(ofSize: 11, weight: .semibold), color: ink,
                      rect: CGRect(x: x, y: cy, width: colWidth, height: 16))
            cy += 22

            let fields: [(label: String, value: String?, big: Bool)] = [
                ("Signature", signature, true),
                ("Printed Name / Title", printedName, false),
                ("Date", date, false),
                ("Email / Phone", contact.isEmpty ? nil : contact, false)
            ]
            for field in fields {
                let lineY = cy + 24
                if let value = field.value, !value.isEmpty {
                    let font = field.big ? UIFont.systemFont(ofSize: 14, weight: .semibold) : UIFont.systemFont(ofSize: 9.5)
                    drawFixed(value, font: font, color: ink,
                              rect: CGRect(x: x, y: lineY - (field.big ? 19 : 14), width: colWidth, height: field.big ? 19 : 13))
                }
                shortLine(x: x, y: lineY, width: colWidth)
                var label = field.label
                if field.big, let note = signatureNote { label += " — \(note)" }
                drawFixed(label, font: .systemFont(ofSize: 8), color: muted,
                          rect: CGRect(x: x, y: lineY + 3, width: colWidth, height: 11))
                cy += 38
            }
        }

        column(x: leftX, role: "SERVICE PROVIDER", party: businessName, signature: nil, signatureNote: nil,
               printedName: nil, date: nil, contact: providerContact)
        column(x: rightX, role: "CLIENT", party: clientName, signature: signed?.name, signatureNote: signed?.method,
               printedName: signed?.name, date: signed?.date, contact: clientContact)

        y = top + 13 + 22 + 38 * 4 + 12
    }

    // MARK: Drawing helpers

    private func paragraphStyle(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1.5
        return style
    }

    private func attributed(_ text: String, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left,
                            kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle(alignment), .kern: kern
        ])
    }

    private func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let m = NSMutableAttributedString(attributedString: text)
        m.addAttribute(.paragraphStyle, value: paragraphStyle(.left), range: NSRange(location: 0, length: m.length))
        let rect = m.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    private func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        measure(attributed(text.isEmpty ? " " : text, font: font, color: ink), width: width)
    }

    /// Draws in a fixed rect, wherever the cursor is.
    private func drawFixed(_ text: String, font: UIFont, color: UIColor, rect: CGRect,
                           alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        attributed(text, font: font, color: color, alignment: alignment, kern: kern)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
    }

    /// Draws at the cursor and moves it down, continuing on the next page
    /// when the text runs past the bottom margin.
    private mutating func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat, width: CGFloat,
                               alignment: NSTextAlignment = .left, kern: CGFloat = 0, keep: CGFloat = 0) {
        if keep > 0 { ensureSpace(keep) }
        drawFlowing(attributed(text, font: font, color: color, alignment: alignment, kern: kern), x: x, width: width)
    }

    private mutating func drawFlowing(_ text: NSAttributedString, x: CGFloat, width: CGFloat) {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var glyphStart = 0
        let totalGlyphs = manager.numberOfGlyphs

        while true {
            let available = max(contentBottom - y, 0)
            let container = NSTextContainer(size: CGSize(width: width, height: available))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let range = manager.glyphRange(for: container)
            if range.length > 0 {
                let used = manager.usedRect(for: container)
                manager.drawGlyphs(forGlyphRange: range, at: CGPoint(x: x, y: y))
                y += ceil(used.height)
                glyphStart = NSMaxRange(range)
            }
            if glyphStart >= totalGlyphs { break }
            beginPage()
        }
    }

    private func line(y: CGFloat, color: UIColor, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: marginX, y: y))
        path.addLine(to: CGPoint(x: pageWidth - marginX, y: y))
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private func shortLine(x: CGFloat, y: CGFloat, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + width, y: y))
        UIColor(white: 0.55, alpha: 1).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }
}
