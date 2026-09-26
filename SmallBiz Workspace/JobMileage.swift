import CoreLocation
import Foundation

/// Distance between two jobs' recorded locations, and the resulting
/// mileage-expense math. A small, single-purpose set of static funcs, same
/// shape as `JobInvoiceBuilder`/`EstimateToInvoiceConverter` — logic a view
/// calls, not logic a view owns.
enum JobMileage {
    /// nil when either job has no recorded location (Job.latitude/longitude
    /// are only set once the owner captures location at the job site).
    static func miles(from: Job, to: Job) -> Double? {
        guard let fromLat = from.latitude, let fromLon = from.longitude,
              let toLat = to.latitude, let toLon = to.longitude else { return nil }

        let a = CLLocation(latitude: fromLat, longitude: fromLon)
        let b = CLLocation(latitude: toLat, longitude: toLon)
        let meters = a.distance(from: b)
        return meters * 0.000621371
    }

    /// The most recent earlier job (by start date) in the same business
    /// that has a recorded location. Jobs still waiting to be scheduled are
    /// excluded — `needsScheduling` means `startDate` is a placeholder, not
    /// real history (see Job.swift).
    static func previousJob(before job: Job, in jobs: [Job]) -> Job? {
        jobs
            .filter {
                $0.id != job.id
                    && !$0.needsScheduling
                    && $0.latitude != nil
                    && $0.longitude != nil
                    && $0.startDate < job.startDate
            }
            .max { $0.startDate < $1.startDate }
    }

    static func estimatedDeductionCents(
        miles: Double,
        ratePerMileCents: Int = IRSMileageRate.currentCentsPerMile
    ) -> Int {
        Int((miles * Double(ratePerMileCents)).rounded())
    }
}

enum IRSMileageRate {
    /// 2025 IRS standard mileage rate for business use, in cents per mile.
    /// The IRS publishes a new rate each January (irs.gov/tax-professionals/
    /// standard-mileage-rates) and there's no API for it — update this
    /// constant by hand when it changes. Expenses already logged keep the
    /// rate that was current when they were created
    /// (`Expense.mileageRateCentsPerMile`), so a later update here never
    /// changes a past expense's amount.
    static let currentCentsPerMile = 70
}
