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
            guard existing.isEmpty else { return }

            let general = ContractTemplate(
                name: "General Service Agreement",
                category: "General",
                body: defaultGeneralTemplate(),
                isBuiltIn: true,
                version: 1
            )

            let photo = ContractTemplate(
                name: "Photography Agreement (Basic)",
                category: "Photography",
                body: defaultPhotoTemplate(),
                isBuiltIn: true,
                version: 1
            )

            let dj = ContractTemplate(
                name: "DJ Services Agreement (Basic)",
                category: "DJ",
                body: defaultDJTemplate(),
                isBuiltIn: true,
                version: 1
            )

            context.insert(general)
            context.insert(photo)
            context.insert(dj)

            try context.save()
            print("✅ Seeded default contract templates (3)")
        } catch {
            print("❌ ContractTemplateSeeder failed: \(error)")
        }
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
}
