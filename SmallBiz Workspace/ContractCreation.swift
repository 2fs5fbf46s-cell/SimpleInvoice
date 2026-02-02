import Foundation
import SwiftData

enum ContractCreation {
    static func create(
        context: ModelContext,
        template: ContractTemplate,
        // ✅ Pass the active businessID from ActiveBusinessStore
        businessID: UUID,
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        extras: [String: String] = [:]
    ) throws -> Contract {

        // ✅ Safety check: if a client/invoice exists, ensure it matches the businessID we’re creating under.
        if let c = client, c.businessID != businessID {
            print("⚠️ ContractCreation: client.businessID != active businessID (client will still be linked).")
        }
        if let inv = invoice, inv.businessID != businessID {
            print("⚠️ ContractCreation: invoice.businessID != active businessID (invoice will still be linked).")
        }

        let ctx = ContractContext(
            business: business,
            client: client,
            invoice: invoice,
            extras: extras
        )

        let rendered = ContractTemplateEngine.render(template: template.body, context: ctx)

        let contract = Contract(
            title: template.name,
            templateName: template.name,
            templateCategory: template.category,
            renderedBody: rendered,
            statusRaw: ContractStatus.draft.rawValue,
            client: client,
            invoice: invoice
        )

        // ✅ The ONLY correct businessID source:
        contract.businessID = businessID
        contract.updatedAt = .now

        context.insert(contract)
        try context.save()
        return contract
    }
}
