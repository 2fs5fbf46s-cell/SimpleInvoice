import Foundation

extension MusicSplitSheetDraft {
    func contractBody(preparedBy business: BusinessProfile? = nil, generatedAt: Date = .now) -> String {
        let preparedBy = business?.name.trimmedForMusicSplitSheet ?? ""
        let preparedByLine = preparedBy.isEmpty ? "" : "\nPrepared By: \(preparedBy)"
        let contributorDetails = contributors.enumerated().map { index, contributor in
            """
            Contributor \(index + 1)
            Legal Name: \(value(contributor.legalName))
            Stage Name / Company: \(value(contributor.stageNameOrCompany))
            Role: \(value(contributor.role))
            Email: \(value(contributor.email))
            Phone: \(value(contributor.phone))
            PRO Affiliation: \(value(contributor.proAffiliation))
            IPI / CAE Number: \(value(contributor.ipiCaeNumber))
            Publisher Name: \(value(contributor.publisherName))
            """
        }.joined(separator: "\n\n")

        let publishingRows = contributors.map {
            "\($0.displayName) | \(value($0.role)) | \(percent($0.writerSharePercent)) | \(percent($0.publishingSharePercent))"
        }.joined(separator: "\n")

        let masterRows = contributors.map {
            "\($0.displayName) | \(percent($0.masterOwnershipPercent)) | \(percent($0.producerPointsPercent)) | \(value($0.royaltyNotes))"
        }.joined(separator: "\n")

        let workForHireRows = contributors.map { contributor in
            let status = contributor.isWorkForHire ? "Yes" : "No"
            let flatFee = value(contributor.flatFeeAmount)
            let paidDate = value(contributor.flatFeePaidDate)
            let notes = value(contributor.royaltyNotes)
            return "\(contributor.displayName): Work-for-hire: \(status). Flat fee: \(flatFee). Paid date: \(paidDate). Royalty notes: \(notes)."
        }.joined(separator: "\n")

        let sampleText: String
        if usesSamples {
            sampleText = """
            Samples / Interpolations Used: Yes
            Sample Source: \(value(sampleSource))
            Clearance Responsibility: \(value(clearanceResponsibility))
            Clearance Status: \(value(clearanceStatus))
            """
        } else {
            sampleText = """
            Samples / Interpolations Used: No
            Sample Source: Not applicable
            Clearance Responsibility: Not applicable
            Clearance Status: \(value(clearanceStatus))
            """
        }

        let signatureBlocks = contributors.map { contributor in
            """
            Contributor Name: \(contributor.displayName)
            Signature: ______________________________
            Date: __________________
            """
        }.joined(separator: "\n\n")

        return """
        MUSIC SPLIT SHEET

        Date Prepared: \(Self.dateString(generatedAt))\(preparedByLine)

        1. SONG INFORMATION
        Song Title: \(value(songTitle))
        Artist / Performing Artist: \(value(artistName))
        Alternate Title(s): \(value(alternateTitles))
        Date Created: \(value(dateCreated))
        Recording Location / Studio: \(value(recordingLocation))
        ISRC / Release Info: \(value(isrc))
        Release Date: \(value(releaseDate))
        Distributor: \(value(distributor))

        2. CONTRIBUTORS
        \(contributorDetails.isEmpty ? "No contributors listed." : contributorDetails)

        3. SONGWRITING / PUBLISHING SPLITS
        Contributor | Role | Writer Share | Publishing Share
        \(publishingRows.isEmpty ? "No publishing splits listed." : publishingRows)

        Writer Share Total: \(percent(writerShareTotal))
        Publishing Share Total: \(percent(publishingShareTotal))
        Total songwriting and publishing splits must equal 100%.

        4. MASTER RECORDING SPLITS
        Contributor | Master Ownership | Producer Royalty / Points | Mechanical / Streaming Payout Notes
        \(masterRows.isEmpty ? "No master recording splits listed." : masterRows)

        Master Ownership Total: \(percent(masterOwnershipTotal))
        Total master recording splits must equal 100%.

        5. WORK-FOR-HIRE / BUYOUT TERMS
        \(workForHireRows.isEmpty ? "No work-for-hire or buyout terms listed." : workForHireRows)

        A listed flat fee only replaces future royalties if that treatment is stated in the royalty notes or otherwise agreed to in writing by the affected parties.

        6. SAMPLES / INTERPOLATIONS
        \(sampleText)

        7. DISTRIBUTION / ADMINISTRATION
        Distributor: \(value(distributor))
        Release Date: \(value(releaseDate))
        PRO / Publishing Admin Registration Responsibility: \(value(proRegistrationResponsibleParty))
        Distributor Upload Responsibility: \(value(distributorUploadResponsibleParty))
        Payment Reporting Schedule: \(value(paymentReportingSchedule))

        8. AGREEMENT TERMS
        All parties agree that the percentages listed in this split sheet represent their agreed ownership and/or royalty participation for the song and master recording identified above. Any future changes must be agreed to in writing by all affected parties.

        Each party confirms that the information they provide is accurate and that they have authority to agree to the splits and terms listed in this document.

        9. SIGNATURES
        \(signatureBlocks.isEmpty ? "Contributor Name: ______________________________\nSignature: ______________________________\nDate: __________________" : signatureBlocks)
        """
    }

    private func value(_ text: String) -> String {
        let trimmed = text.trimmedForMusicSplitSheet
        return trimmed.isEmpty ? "[Not specified]" : trimmed
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
