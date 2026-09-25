import SwiftData
import SwiftUI

struct SBWCardContainer<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SummaryKit.SummaryCard {
            content
        }
    }
}

struct SBWSectionHeaderRow: View {
    let title: String
    let subtitle: String?
    let status: String?

    init(title: String, subtitle: String? = nil, status: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    var body: some View {
        SummaryKit.SummaryHeader(title: title, subtitle: subtitle, status: status)
    }
}

struct SBWStatusPill: View {
    let text: String

    var body: some View {
        SummaryKit.StatusChip(text: text)
    }
}

struct InvoiceOverviewView: View {
    @Bindable var invoice: Invoice

    var body: some View {
        // Invoices and estimates have one screen each, built around their
        // next step. The summary page in front of the editor is gone.
        InvoiceDetailView(invoice: invoice)
    }
}

struct BookingOverviewView: View {
    let request: BookingRequestItem
    let onStatusChange: (BookingRequestItem) -> Void

    init(request: BookingRequestItem, onStatusChange: @escaping (BookingRequestItem) -> Void = { _ in }) {
        self.request = request
        self.onStatusChange = onStatusChange
    }

    var body: some View {
        BookingDetailView(request: request, onStatusChange: onStatusChange)
    }
}


// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// Compared by what it shows; callbacks and bindings are ignored.
extension BookingOverviewView: Equatable {
    static func == (lhs: BookingOverviewView, rhs: BookingOverviewView) -> Bool {
        lhs.request == rhs.request
    }
}
