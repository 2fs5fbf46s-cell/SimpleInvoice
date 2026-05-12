//
//  ContractTemplateSeeder.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

enum ContractTemplateSeeder {

    static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ContractTemplate>()
            let existing = try context.fetch(descriptor)
            let existingNames = Set(existing.map { normalizedName($0.name) })
            let missingTemplates = builtInTemplates()
                .filter { !existingNames.contains(normalizedName($0.name)) }

            guard !missingTemplates.isEmpty else { return }

            for template in missingTemplates {
                context.insert(template)
            }

            try context.save()
            print("✅ Seeded default contract templates (\(missingTemplates.count))")
        } catch {
            print("❌ ContractTemplateSeeder failed: \(error)")
        }
    }

    private static func builtInTemplates() -> [ContractTemplate] {
        [
            ContractTemplate(
                name: "General Service Agreement",
                category: "General",
                body: defaultGeneralTemplate(),
                isBuiltIn: true,
                version: 1
            ),
            ContractTemplate(
                name: "Photography Agreement (Basic)",
                category: "Photography",
                body: defaultPhotoTemplate(),
                isBuiltIn: true,
                version: 1
            ),
            ContractTemplate(
                name: "DJ Services Agreement (Basic)",
                category: "DJ",
                body: defaultDJTemplate(),
                isBuiltIn: true,
                version: 1
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

    private static func defaultGeneralTemplate() -> String {
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

    private static func defaultPhotoTemplate() -> String {
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

    private static func defaultDJTemplate() -> String {
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
