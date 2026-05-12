import Foundation

struct MusicSplitSheetContributor: Identifiable, Equatable {
    var id: UUID = UUID()
    var legalName: String = ""
    var stageNameOrCompany: String = ""
    var role: String = MusicSplitSheetContributor.roles.first ?? "Writer"
    var email: String = ""
    var phone: String = ""
    var proAffiliation: String = ""
    var ipiCaeNumber: String = ""
    var publisherName: String = ""
    var writerSharePercent: Double = 0
    var publishingSharePercent: Double = 0
    var masterOwnershipPercent: Double = 0
    var producerPointsPercent: Double = 0
    var isWorkForHire: Bool = false
    var flatFeeAmount: String = ""
    var flatFeePaidDate: String = ""
    var royaltyNotes: String = ""

    static let roles = [
        "Writer",
        "Producer",
        "Artist",
        "Featured Artist",
        "Engineer",
        "Mixer",
        "Mastering Engineer",
        "Publisher",
        "Other"
    ]

    var displayName: String {
        let trimmedName = legalName.trimmedForMusicSplitSheet
        if !trimmedName.isEmpty { return trimmedName }

        let stage = stageNameOrCompany.trimmedForMusicSplitSheet
        if !stage.isEmpty { return stage }

        return "Unnamed Contributor"
    }
}

struct MusicSplitSheetDraft: Equatable {
    static let templateName = "Music Split Sheet (Smart Form)"
    static let templateCategory = "Music / Entertainment"
    static let smartFormSearchText = """
    music split sheet smart form music entertainment define songwriting publishing master recording producer contributor splits before release royalty percentage validation
    """

    var songTitle: String = ""
    var artistName: String = ""
    var alternateTitles: String = ""
    var dateCreated: String = ""
    var recordingLocation: String = ""
    var isrc: String = ""
    var releaseDate: String = ""
    var distributor: String = ""

    var contributors: [MusicSplitSheetContributor] = []

    var usesSamples: Bool = false
    var sampleSource: String = ""
    var clearanceResponsibility: String = ""
    var clearanceStatus: String = "Not Required"

    var proRegistrationResponsibleParty: String = ""
    var distributorUploadResponsibleParty: String = ""
    var paymentReportingSchedule: String = ""

    static let clearanceStatuses = [
        "Not Required",
        "Pending",
        "Cleared",
        "Denied",
        "Unknown"
    ]

    var writerShareTotal: Double {
        contributors.reduce(0) { $0 + $1.writerSharePercent }
    }

    var publishingShareTotal: Double {
        contributors.reduce(0) { $0 + $1.publishingSharePercent }
    }

    var masterOwnershipTotal: Double {
        contributors.reduce(0) { $0 + $1.masterOwnershipPercent }
    }

    var validationWarnings: [String] {
        splitValidationWarnings()
    }

    func validationWarnings(selectedClient: Client?) -> [String] {
        var warnings: [String] = []

        if selectedClient == nil {
            warnings.append("Select a client before generating the split sheet.")
        }

        warnings.append(contentsOf: splitValidationWarnings())
        return warnings
    }

    func canGenerateContract(selectedClient: Client?) -> Bool {
        validationWarnings(selectedClient: selectedClient).isEmpty
    }

    func makeContract(
        businessID: UUID,
        business: BusinessProfile?,
        selectedClient: Client,
        linkedJob: Job? = nil,
        linkedInvoice: Invoice? = nil,
        generatedAt: Date = .now
    ) -> Contract {
        let resolvedJob = linkedJob ?? linkedInvoice?.job
        let contract = Contract(
            businessID: businessID,
            title: contractTitle,
            createdAt: generatedAt,
            updatedAt: generatedAt,
            templateName: Self.templateName,
            templateCategory: Self.templateCategory,
            renderedBody: contractBody(preparedBy: business, generatedAt: generatedAt),
            statusRaw: ContractStatus.draft.rawValue,
            client: selectedClient,
            invoice: linkedInvoice,
            linkedJobIDsCSV: resolvedJob?.id.uuidString ?? ""
        )

        contract.job = resolvedJob
        contract.portalNeedsUpload = true
        return contract
    }

    var contractTitle: String {
        let title = songTitle.trimmedForMusicSplitSheet
        return title.isEmpty ? "Music Split Sheet" : "Music Split Sheet - \(title)"
    }

    private func splitValidationWarnings() -> [String] {
        var warnings: [String] = []

        if contributors.isEmpty {
            warnings.append("Add at least one contributor.")
        }

        appendTotalWarning(
            total: writerShareTotal,
            label: "Writer share total",
            to: &warnings
        )
        appendTotalWarning(
            total: publishingShareTotal,
            label: "Publishing share total",
            to: &warnings
        )
        appendTotalWarning(
            total: masterOwnershipTotal,
            label: "Master ownership total",
            to: &warnings
        )

        for (index, contributor) in contributors.enumerated() {
            let contributorLabel = contributor.displayName == "Unnamed Contributor"
                ? "Contributor \(index + 1)"
                : contributor.displayName

            if contributor.legalName.trimmedForMusicSplitSheet.isEmpty {
                warnings.append("\(contributorLabel) is missing a legal name.")
            }

            appendPercentWarnings(
                value: contributor.writerSharePercent,
                field: "Writer share",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.publishingSharePercent,
                field: "Publishing share",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.masterOwnershipPercent,
                field: "Master ownership",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.producerPointsPercent,
                field: "Producer points",
                contributor: contributorLabel,
                to: &warnings
            )
        }

        return warnings
    }

    var canGenerateContract: Bool {
        validationWarnings.isEmpty
    }

    private func appendTotalWarning(total: Double, label: String, to warnings: inout [String]) {
        guard abs(total - 100) > 0.01 else { return }
        warnings.append("\(label) must equal 100%. Current total: \(percent(total)).")
    }

    private func appendPercentWarnings(
        value: Double,
        field: String,
        contributor: String,
        to warnings: inout [String]
    ) {
        if value < 0 {
            warnings.append("\(contributor) \(field.lowercased()) cannot be negative.")
        }

        if value > 100 {
            warnings.append("\(contributor) \(field.lowercased()) should not exceed 100%.")
        }
    }
}

func percent(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))%"
    }

    return String(format: "%.2f%%", value)
}

extension String {
    var trimmedForMusicSplitSheet: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
