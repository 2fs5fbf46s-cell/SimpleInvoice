//
//  ContractTemplateSeeder.swift
//  SmallBiz Workspace
//

import Foundation
import OSLog
import SwiftData

enum ContractTemplateSeeder {

    /// Bump when a built-in template's canned text changes below. Seeding
    /// only ever inserts templates that don't exist yet by name; upgrading
    /// existing ones is `upgradeBuiltInTemplatesIfNeeded`'s job, and it only
    /// touches a template whose body still matches a known-previous version
    /// word for word — the template detail screen explicitly invites editing
    /// a built-in template's text ("You can change its text"), so an owner's
    /// own rewrite is never overwritten just because the app shipped a
    /// better default.
    private static let currentVersion = 2

    static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ContractTemplate>()
            let existing = try context.fetch(descriptor)
            let existingNames = Set(existing.map { normalizedName($0.name) })
            let missingTemplates = builtInTemplates()
                .filter { !existingNames.contains(normalizedName($0.name)) }

            for template in missingTemplates {
                context.insert(template)
            }

            let upgraded = upgradeBuiltInTemplatesIfNeeded(existing: existing)

            guard !missingTemplates.isEmpty || upgraded > 0 else { return }

            try context.save()
            if !missingTemplates.isEmpty {
                SBWLog.data.note("✅ Seeded default contract templates (\(missingTemplates.count))")
            }
            if upgraded > 0 {
                SBWLog.data.note("✅ Upgraded built-in contract templates to v\(currentVersion) (\(upgraded))")
            }
        } catch {
            SBWLog.data.problem("❌ ContractTemplateSeeder failed: \(error)")
        }
    }

    /// Replaces an existing built-in template's body with the current canned
    /// text, but only when its stored body still matches a version we shipped
    /// before (i.e. nobody has edited it) and its version is behind. Returns
    /// how many templates were upgraded.
    private static func upgradeBuiltInTemplatesIfNeeded(existing: [ContractTemplate]) -> Int {
        var upgradedCount = 0
        let current = Dictionary(uniqueKeysWithValues: builtInTemplates().map { (normalizedName($0.name), $0) })
        let legacy = Dictionary(uniqueKeysWithValues: legacyV1Templates().map { (normalizedName($0.name), $0) })

        for template in existing where template.isBuiltIn {
            guard template.version < currentVersion else { continue }
            let key = normalizedName(template.name)
            guard let currentDefault = current[key] else { continue }

            let untouched = template.body == currentDefault.body
                || (legacy[key].map { template.body == $0.body } ?? false)
            guard untouched else { continue }

            template.body = currentDefault.body
            template.version = currentVersion
            upgradedCount += 1
        }

        return upgradedCount
    }

    private static func builtInTemplates() -> [ContractTemplate] {
        [
            ContractTemplate(
                name: "General Service Agreement",
                category: "General",
                body: defaultGeneralTemplate(),
                isBuiltIn: true,
                version: currentVersion
            ),
            ContractTemplate(
                name: "Photography Agreement (Basic)",
                category: "Photography",
                body: defaultPhotoTemplate(),
                isBuiltIn: true,
                version: currentVersion
            ),
            ContractTemplate(
                name: "DJ Services Agreement (Basic)",
                category: "DJ",
                body: defaultDJTemplate(),
                isBuiltIn: true,
                version: currentVersion
            ),
            ContractTemplate(
                name: "Music Split Sheet",
                category: "Music / Entertainment",
                body: defaultMusicSplitSheetTemplate(),
                isBuiltIn: true,
                version: 1
            )
        ]
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Shared clauses

    /// The clauses that barely differ between a photo shoot and a fence
    /// repair: schedule/change orders, cancellation, liability, insurance,
    /// force majeure, governing law, and entire-agreement. Written out once
    /// here so General/Photography/DJ stay identical where they should be —
    /// only the scope, delivery and trade-specific sections vary by template.
    private static func standardClauses(startingAt n: Int) -> String {
        """
        \(n). SCHEDULE & CHANGE ORDERS
        The date and time above are confirmed once both parties sign. Work outside the scope described in this Agreement is a change order: it will be described and priced in writing and both parties must agree to it before it begins.

        \(n + 1). CANCELLATION & RESCHEDULING
        Either party may reschedule with at least 48 hours' notice before the scheduled date. A cancellation made with less than 48 hours' notice forfeits the deposit. If the Client cancels after work has begun, the Client owes payment for work completed and materials already purchased, less any deposit already paid.

        \(n + 2). LIMITATION OF LIABILITY
        The Provider's total liability under this Agreement is limited to the amounts actually paid by the Client. Neither party is liable to the other for indirect, incidental, or consequential damages, except where such a limit is not permitted by law.

        \(n + 3). INSURANCE
        The Provider carries general liability insurance appropriate to the work described in this Agreement and will provide proof of coverage on request.

        \(n + 4). FORCE MAJEURE
        Neither party is responsible for a delay caused by events beyond their reasonable control, including weather, illness, accident, or a supply shortage. A date affected this way will be rescheduled in good faith at no added cost.

        \(n + 5). GOVERNING LAW & DISPUTES
        This Agreement is governed by the laws of the state in which the Provider operates. Before either party pursues any other remedy, the parties will first attempt to resolve a dispute informally between themselves.

        \(n + 6). ENTIRE AGREEMENT
        This document, together with the invoice or estimate it references, is the entire agreement between the parties and replaces any earlier discussion or proposal on the same work. A change to its terms is only valid in writing, signed by both parties.
        """
    }

    private static func partiesSection() -> String {
        """
        Provider: {{Business.Name}}
        {{Business.ContactLine}}
        {{Business.Address}}

        Client: {{Client.Name}}
        {{Client.ContactLine}}
        {{Client.Address}}
        """
    }

    private static func projectSection() -> String {
        """
        2. PROJECT
        {{Job.Title}}
        Site: {{Job.Location}}
        Scheduled: {{Job.Date}}
        Reference: Invoice {{Invoice.Number}}
        {{Job.Measurements}}
        """
    }

    private static func paymentSection(_ n: Int) -> String {
        """
        \(n). PAYMENT SCHEDULE
        Total: {{Invoice.Total}}
        Deposit ({{Invoice.DepositDueDate}}): {{Invoice.Deposit}}
        Balance ({{Invoice.BalanceDueDate}}): {{Invoice.Balance}}
        Payment terms: {{Invoice.PaymentTerms}}
        """
    }

    private static func signatureBlock() -> String {
        """
        Provider Signature: _______________________   Printed Name: _______________________   Date: __________
        Client Signature: _________________________   Printed Name: _______________________   Date: __________
        """
    }

    // MARK: - Templates

    private static func defaultGeneralTemplate() -> String {
        """
        SERVICE AGREEMENT

        This Service Agreement (“Agreement”) is made on {{Today}} between:

        \(partiesSection())

        1. SCOPE OF SERVICES
        The Provider agrees to perform the following:
        {{Invoice.Items}}

        \(projectSection())

        \(paymentSection(4))

        \(standardClauses(startingAt: 5))

        \(signatureBlock())
        """
    }

    private static func defaultPhotoTemplate() -> String {
        """
        PHOTOGRAPHY AGREEMENT

        This Photography Agreement (“Agreement”) is made on {{Today}} between:

        \(partiesSection())

        1. SERVICES
        The Photographer will provide the photography services described below:
        {{Invoice.Items}}

        \(projectSection())

        \(paymentSection(4))

        5. DELIVERY
        Edited images will be delivered digitally within a timeline communicated to the Client after the session, unless otherwise agreed in writing.

        6. COPYRIGHT & USAGE
        The Photographer retains copyright in all images produced under this Agreement. The Client receives a license for personal use unless commercial or extended usage is agreed to separately in writing.

        \(standardClauses(startingAt: 7))

        \(signatureBlock())
        """
    }

    private static func defaultDJTemplate() -> String {
        """
        DJ SERVICES AGREEMENT

        This DJ Services Agreement (“Agreement”) is made on {{Today}} between:

        \(partiesSection())

        1. SERVICES
        The DJ/Provider will provide the services described below:
        {{Invoice.Items}}

        \(projectSection())

        \(paymentSection(4))

        5. EVENT REQUIREMENTS
        The Client will provide safe, reasonable access to power and a suitable performance area at the location above, available at least one hour before the scheduled start time for setup.

        \(standardClauses(startingAt: 6))

        \(signatureBlock())
        """
    }

    // MARK: - Legacy (v1) bodies — used only to detect an untouched template
    // when upgrading, never seeded directly.

    private static func legacyV1Templates() -> [ContractTemplate] {
        [
            ContractTemplate(name: "General Service Agreement", category: "General", body: legacyGeneralTemplate(), isBuiltIn: true, version: 1),
            ContractTemplate(name: "Photography Agreement (Basic)", category: "Photography", body: legacyPhotoTemplate(), isBuiltIn: true, version: 1),
            ContractTemplate(name: "DJ Services Agreement (Basic)", category: "DJ", body: legacyDJTemplate(), isBuiltIn: true, version: 1)
        ]
    }

    private static func legacyGeneralTemplate() -> String {
        """
        SERVICE AGREEMENT

        This Service Agreement (“Agreement”) is made on {{Today}} between:

        Provider: {{Business.Name}}
        Email: {{Business.Email}} | Phone: {{Business.Phone}}
        Address: {{Business.Address}}

        Client: {{Client.Name}}
        Email: {{Client.Email}} | Phone: {{Client.Phone}}
        Address: {{Client.Address}}

        1. SCOPE OF SERVICES
        The Provider agrees to perform the services described below:
        {{Invoice.Items}}

        2. FEES & PAYMENT
        Total Amount: {{Invoice.Total}}
        Due Date: {{Invoice.DueDate}}

        3. CANCELLATION / RESCHEDULING
        Client must provide reasonable notice to reschedule. Cancellation terms may apply.

        4. LIMITATION OF LIABILITY
        Provider’s liability is limited to the amounts paid under this Agreement where permitted by law.

        5. ENTIRE AGREEMENT
        This document represents the entire agreement between the parties.

        Provider Signature: _______________________   Date: __________
        Client Signature: _________________________   Date: __________
        """
    }

    private static func legacyPhotoTemplate() -> String {
        """
        PHOTOGRAPHY AGREEMENT

        Date: {{Today}}
        Photographer: {{Business.Name}} ({{Business.Email}} | {{Business.Phone}})
        Client: {{Client.Name}} ({{Client.Email}} | {{Client.Phone}})

        1. SERVICES
        The Photographer will provide photography services as described:
        {{Invoice.Items}}

        2. FEES
        Package Total: {{Invoice.Total}}
        Invoice Number: {{Invoice.Number}}
        Due Date: {{Invoice.DueDate}}

        3. DELIVERY
        Delivery timeline and method will be communicated after the session.

        4. COPYRIGHT & USAGE
        Photographer retains copyright. Client receives personal usage rights unless otherwise stated.

        5. CANCELLATION / RESCHEDULE
        Rescheduling requires reasonable notice. Deposits/fees may be non-refundable depending on timing.

        Photographer Signature: ____________________  Date: __________
        Client Signature: __________________________  Date: __________
        """
    }

    private static func legacyDJTemplate() -> String {
        """
        DJ SERVICES AGREEMENT

        Date: {{Today}}
        DJ/Provider: {{Business.Name}}
        Client: {{Client.Name}}

        1. SERVICES
        DJ services as described below:
        {{Invoice.Items}}

        2. FEES
        Total: {{Invoice.Total}}
        Due: {{Invoice.DueDate}}

        3. EVENT REQUIREMENTS
        Client will provide safe access to power and a suitable performance area.

        4. CANCELLATION
        Cancellation terms depend on notice given.

        DJ/Provider Signature: _____________________ Date: __________
        Client Signature: __________________________ Date: __________
        """
    }

    private static func defaultMusicSplitSheetTemplate() -> String {
        """
        MUSIC SPLIT SHEET

        Purpose: Define songwriting, publishing, master recording, producer, and contributor splits before release.
        Date Prepared: {{Today}}

        1. SONG INFORMATION
        Song Title: [Song Title]
        Artist / Performing Artist: [Artist Name]
        Alternate Title(s): [Alternate Title(s)]
        Date Created: [Date Created]
        Recording Location / Studio: [Recording Location / Studio]
        ISRC / Release Info: [ISRC / Release Info]

        2. CONTRIBUTORS
        Contributor 1
        Legal Name: [Contributor Name]
        Stage Name / Company: [Stage Name / Company]
        Role: [Writer / Producer / Artist / Featured Artist / Engineer / Mixer / Mastering Engineer / Publisher / Other]
        Email / Phone: [Email / Phone]
        PRO Affiliation: [PRO]
        IPI / CAE Number: [IPI/CAE]
        Publisher Name: [Publisher Name]

        Contributor 2
        Legal Name: [Contributor Name]
        Stage Name / Company: [Stage Name / Company]
        Role: [Writer / Producer / Artist / Featured Artist / Engineer / Mixer / Mastering Engineer / Publisher / Other]
        Email / Phone: [Email / Phone]
        PRO Affiliation: [PRO]
        IPI / CAE Number: [IPI/CAE]
        Publisher Name: [Publisher Name]

        3. SONGWRITING / PUBLISHING SPLITS
        Contributor: [Contributor Name]
        Role: [Role]
        Publishing Share Percentage: [Percentage]
        Writer Share Percentage: [Percentage]

        Contributor: [Contributor Name]
        Role: [Role]
        Publishing Share Percentage: [Percentage]
        Writer Share Percentage: [Percentage]

        Total Publishing Share: 100%
        Total Writer Share: 100%
        Total songwriting and publishing splits must equal 100%.

        4. MASTER RECORDING SPLITS
        Contributor: [Contributor Name]
        Master Ownership Percentage: [Percentage]
        Producer Royalty / Points: [Producer Royalty / Points]
        Mechanical / Streaming Payout Notes: [Payout Notes]

        Contributor: [Contributor Name]
        Master Ownership Percentage: [Percentage]
        Producer Royalty / Points: [Producer Royalty / Points]
        Mechanical / Streaming Payout Notes: [Payout Notes]

        Total Master Ownership: 100%
        Total master recording splits must equal 100%.

        5. WORK-FOR-HIRE / BUYOUT TERMS
        Any contributor work-for-hire? [Yes / No]
        Contributor(s): [Contributor Name]
        Flat Fee Paid? [Yes / No]
        Payment Amount: [Amount]
        Payment Date: [Date]
        Does the fee replace future royalties? [Yes / No]
        Notes: [Work-for-Hire / Buyout Notes]

        6. SAMPLES / INTERPOLATIONS
        Any Samples Used? [Yes / No]
        Sample Source: [Sample Source]
        Clearance Responsibility: [Responsible Party]
        Clearance Status: [Cleared / Pending / Not Required]
        Notes: [Sample / Interpolation Notes]

        7. DISTRIBUTION / ADMINISTRATION
        Distributor: [Distributor]
        Release Date: [Release Date]
        PRO / Publishing Admin Registration Responsibility: [Responsible Party]
        Distributor Upload Responsibility: [Responsible Party]
        Payment Reporting Schedule: [Monthly / Quarterly / Other]

        8. AGREEMENT TERMS
        All parties agree that the percentages listed in this split sheet represent their agreed ownership and/or royalty participation for the song and master recording identified above. Any future changes must be agreed to in writing by all affected parties.

        Each party confirms that the information they provide is accurate and that they have authority to agree to the splits and terms listed in this document.

        9. SIGNATURES
        Contributor Name: [Contributor Name]
        Signature: ______________________________
        Date: __________________

        Contributor Name: [Contributor Name]
        Signature: ______________________________
        Date: __________________

        Contributor Name: [Contributor Name]
        Signature: ______________________________
        Date: __________________
        """
    }
}
