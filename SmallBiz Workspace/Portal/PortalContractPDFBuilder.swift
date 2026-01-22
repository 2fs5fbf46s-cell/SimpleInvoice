import Foundation
import UIKit

enum PortalContractPDFBuilder {
    
    private static func latestClientSignature(for contract: Contract) -> ContractSignature? {
        let sigs = contract.signatures ?? []
        return sigs
            .filter { $0.signerRole == "client" }
            .sorted { $0.signedAt > $1.signedAt }
            .first
    }
    
    
    static func buildContractPDF(
        contract: Contract,
        business: BusinessProfile?
    ) throws -> URL {
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let safeTitle = contract.title.isEmpty ? "Contract" : contract.title
        let fileName = "CONTRACT-\(safeTitle.replacingOccurrences(of: "/", with: "-")).pdf"
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
            
            func hr() {
                y += 6
                let g = UIGraphicsGetCurrentContext()
                g?.setStrokeColor(UIColor.lightGray.cgColor)
                g?.setLineWidth(1)
                g?.move(to: CGPoint(x: left, y: y))
                g?.addLine(to: CGPoint(x: right, y: y))
                g?.strokePath()
                y += 12
            }
            
            // MARK: - Header
            draw("CONTRACT", font: .boldSystemFont(ofSize: 26))
            draw(safeTitle, font: .boldSystemFont(ofSize: 16))
            
            if let biz = business {
                let line = [biz.name, biz.email, biz.phone]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                
                if !line.isEmpty {
                    draw(line, font: .systemFont(ofSize: 12), color: .darkGray)
                }
                if !biz.address.isEmpty {
                    draw(biz.address, font: .systemFont(ofSize: 12), color: .darkGray)
                }
            }
            
            hr()
            
            // MARK: - Client
            draw("Client", font: .boldSystemFont(ofSize: 14))
            
            if let c = contract.client {
                let clientLines = [c.name, c.email, c.phone, c.address]
                    .filter { !$0.isEmpty }
                
                draw(
                    clientLines.isEmpty ? "Client linked (no details)." : clientLines.joined(separator: "\n"),
                    font: .systemFont(ofSize: 12)
                )
            } else {
                draw("No client linked", font: .systemFont(ofSize: 12), color: .darkGray)
            }
            
            hr()
            
            // MARK: - Linked Records
            draw("Linked Records", font: .boldSystemFont(ofSize: 14))
            
            if let est = contract.estimate {
                draw("• Estimate: \(est.invoiceNumber)", font: .systemFont(ofSize: 12))
            }
            if let inv = contract.invoice {
                draw("• Invoice: \(inv.invoiceNumber)", font: .systemFont(ofSize: 12))
            }
            if let job = contract.job {
                draw("• Job: \(job.title)", font: .systemFont(ofSize: 12))
            }
            
            if contract.estimate == nil && contract.invoice == nil && contract.job == nil {
                draw("No estimate / invoice / job linked",
                     font: .systemFont(ofSize: 12),
                     color: .darkGray)
            }
            
            hr()
            
            // MARK: - Contract Body
            draw("Agreement", font: .boldSystemFont(ofSize: 14))
            
            let body = contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if body.isEmpty {
                draw("No contract text available.",
                     font: .systemFont(ofSize: 12),
                     color: .darkGray)
            } else {
                draw(body, font: .systemFont(ofSize: 12))
            }
            // MARK: - Signature
            if let sig = latestClientSignature(for: contract) {

                hr()
                draw("Signature", font: .boldSystemFont(ofSize: 14))

                draw(
                    "Signed by: \(sig.signerName)",
                    font: .systemFont(ofSize: 12)
                )

                let dateText = DateFormatter.localizedString(
                    from: sig.signedAt,
                    dateStyle: .medium,
                    timeStyle: .short
                )

                draw(
                    "Signed at: \(dateText)",
                    font: .systemFont(ofSize: 12),
                    color: .darkGray
                )

                draw(
                    "Signed via SmallBiz Workspace Client Portal",
                    font: .systemFont(ofSize: 11),
                    color: .darkGray
                )

                y += 8

                // Render drawn signature image if present
                if sig.signatureType == "drawn",
                   let data = sig.signatureImageData,
                   let image = UIImage(data: data) {

                    let maxWidth: CGFloat = right - left
                    let maxHeight: CGFloat = 120

                    let aspect = image.size.width / max(image.size.height, 1)
                    let width = min(maxWidth, maxHeight * aspect)
                    let height = width / aspect

                    let rect = CGRect(x: left, y: y, width: width, height: height)

                    image.draw(in: rect)
                    y += rect.height + 12
                }

                // Render typed signature fallback
                if sig.signatureType == "typed",
                   let text = sig.signatureText,
                   !text.isEmpty {

                    draw(
                        text,
                        font: UIFont.italicSystemFont(ofSize: 20)
                    )
                }
            }
        }
        
        try data.write(to: url, options: [.atomic])
        return url
    }
}
