import Foundation
import SwiftData

enum ContractCreation {
    static func create(
        context: ModelContext,
        template: ContractTemplate,
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        extras: [String: String] = [:]
    ) throws -> Contract {

        let ctx = ContractContext(
            business: business,
            client: client,
            invoice: invoice,
            extras: extras
        )

        let rendered = ContractTemplateEngine.render(template: template.body, context: ctx)

        let title = template.name

        let contract = Contract(
            title: title,
            templateName: template.name,
            templateCategory: template.category,
            renderedBody: rendered,
            statusRaw: ContractStatus.draft.rawValue,
            client: client,
            invoice: invoice
        )
        contract.businessID = client?.businessID ?? invoice?.businessID ?? UUID()
        contract.updatedAt = .now
    

        context.insert(contract)
        try context.save()
        return contract
    }
}
