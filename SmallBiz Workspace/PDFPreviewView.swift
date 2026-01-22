import SwiftUI
import UIKit
import PDFKit

struct PDFPreviewView: View {
    let url: URL

    var body: some View {
        PDFKitRepresentedView(url: url)
            .navigationTitle("PDF Preview")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .systemBackground

        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            pdfView.document = PDFDocument(url: url)
        }
    }
}
