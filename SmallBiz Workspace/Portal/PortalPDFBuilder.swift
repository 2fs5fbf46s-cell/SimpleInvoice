//
//  PortalPDFBuilder.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/19/26.
//

import Foundation

enum PortalPDFBuilder {

    static func buildInvoicePDF(invoice: Invoice, snapshot: BusinessSnapshot) throws -> URL {
        let fileName = "\(invoice.documentType.uppercased())-\(invoice.invoiceNumber)"
        let data = InvoicePDFGenerator.makePDFData(invoice: invoice, business: snapshot)
        return try InvoicePDFGenerator.writePDFToTemporaryFile(data: data, filename: fileName)
    }
}
