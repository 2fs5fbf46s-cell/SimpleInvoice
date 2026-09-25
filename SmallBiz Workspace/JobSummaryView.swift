import SwiftUI
import SwiftData

/// A job has one screen now — `JobDetailView`, built around its next step.
/// This used to be a separate summary with an Edit button that opened the
/// editor as a sheet, so the same job looked different depending on where
/// you tapped it, and notes typed here could overwrite the editor's. The
/// type stays because the list, clients, bookings and estimates all push it.
struct JobSummaryView: View {
    @Bindable var job: Job

    init(job: Job) {
        self.job = job
    }

    var body: some View {
        JobDetailView(job: job)
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension JobSummaryView: Equatable {
    static func == (lhs: JobSummaryView, rhs: JobSummaryView) -> Bool {
        lhs.job.persistentModelID == rhs.job.persistentModelID
    }
}
