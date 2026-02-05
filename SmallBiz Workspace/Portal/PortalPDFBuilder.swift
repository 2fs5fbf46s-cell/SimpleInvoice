//
//  PortalPDFBuilder.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/19/26.
//

import Foundation

enum PortalPDFBuilder {

    @MainActor
    static func buildInvoicePDF(invoice: Invoice, snapshot: BusinessSnapshot) throws -> URL {
        let fileName = "\(invoice.documentType.uppercased())-\(invoice.invoiceNumber)"
        let resolvedSnapshot = invoice.businessSnapshot ?? snapshot
        let data = InvoicePDFGenerator.makePDFData(invoice: invoice, business: resolvedSnapshot)
        return try InvoicePDFGenerator.writePDFToTemporaryFile(data: data, filename: fileName)
    }
}
