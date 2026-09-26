import Foundation
import OSLog
import SwiftData

enum ContractCreation {
    /// Half up front, half on completion — the founder's standard split.
    /// Callers that already have their own deposit (the estimate-bundling
    /// flow lets the owner type one) pass that instead of calling this.
    static func defaultDepositCents(invoiceTotalCents: Int) -> Int {
        Int((Double(invoiceTotalCents) * 0.5).rounded())
    }

    static func create(
        context: ModelContext,
        template: ContractTemplate,
        // ✅ Pass the active businessID from ActiveBusinessStore
        businessID: UUID,
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        job: Job? = nil,
        depositAmountCents: Int? = nil,
        extras: [String: String] = [:]
    ) throws -> Contract {

        // ✅ Safety check: if a client/invoice exists, ensure it matches the businessID we’re creating under.
        if let c = client, c.businessID != businessID {
            SBWLog.data.problem("⚠️ ContractCreation: client.businessID != active businessID (client will still be linked).")
        }
        if let inv = invoice, inv.businessID != businessID {
            SBWLog.data.problem("⚠️ ContractCreation: invoice.businessID != active businessID (invoice will still be linked).")
        }

        let ctx = ContractContext(
            business: business,
            client: client,
            invoice: invoice,
            job: job,
            depositAmountCents: depositAmountCents,
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
        contract.job = job
        contract.depositAmountCents = depositAmountCents

        // ✅ The ONLY correct businessID source:
        contract.businessID = businessID
        contract.updatedAt = .now

        context.insert(contract)
        try context.save()
        return contract
    }
}
