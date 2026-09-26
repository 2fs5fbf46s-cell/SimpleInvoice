import Foundation
import SwiftData

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case materials
    case fuel
    case software
    case meals
    case equipment
    case mileage
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .materials: return "Materials"
        case .fuel: return "Fuel"
        case .software: return "Software"
        case .meals: return "Meals"
        case .equipment: return "Equipment"
        case .mileage: return "Mileage"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .materials: return "shippingbox"
        case .fuel: return "fuelpump"
        case .software: return "app.badge"
        case .meals: return "fork.knife"
        case .equipment: return "wrench.and.screwdriver"
        case .mileage: return "car.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

@Model
final class Expense {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()

    var amountCents: Int = 0
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var vendor: String = ""
    var date: Date = Foundation.Date()
    var notes: String = ""
    var isTaxDeductible: Bool = true

    // Plain ids rather than relationships, matching Job.clientID: a lightweight
    // link that doesn't need bidirectional traversal from Client/Job yet.
    var clientID: UUID? = nil
    var jobID: UUID? = nil

    /// Set only when this expense was logged from Job-to-Job mileage
    /// (JobMileage), rather than typed in by hand. `mileageRateCentsPerMile`
    /// is a snapshot of the rate at logging time — the IRS publishes a new
    /// one every year, so recomputing it later from `mileageMiles` would
    /// silently change a past expense's amount.
    var mileageMiles: Double? = nil
    var mileageRateCentsPerMile: Int? = nil
    var mileageFromJobID: UUID? = nil

    // Cascade: a join row exists only to link this record to a file. Left to
    // nullify (the default) it survives its owner as an invisible orphan that
    // accumulates forever and syncs to CloudKit. The FileItem itself is not
    // cascaded — it lives in the folder workspace and other records may use it.
    @Relationship(deleteRule: .cascade, inverse: \ExpenseAttachment.expense)
    var attachments: [ExpenseAttachment]? = nil

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Dollar-facing bridge over `amountCents`, the same shape as `category`
    /// over `categoryRaw` — storage stays exact-cents while forms get a plain
    /// `Double` to bind a decimal-pad `TextField` to (mirrors how
    /// `CatalogItem.unitPrice` is entered).
    var amountDollars: Double {
        get { Double(amountCents) / 100.0 }
        set { amountCents = Int((newValue * 100).rounded()) }
    }

    init(
        businessID: UUID,
        amountCents: Int = 0,
        category: ExpenseCategory = .other,
        vendor: String = "",
        date: Date = Foundation.Date(),
        notes: String = "",
        isTaxDeductible: Bool = true,
        clientID: UUID? = nil,
        jobID: UUID? = nil
    ) {
        self.businessID = businessID
        self.amountCents = amountCents
        self.categoryRaw = category.rawValue
        self.vendor = vendor
        self.date = date
        self.notes = notes
        self.isTaxDeductible = isTaxDeductible
        self.clientID = clientID
        self.jobID = jobID
    }
}
