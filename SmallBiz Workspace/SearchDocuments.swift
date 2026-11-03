import Foundation
import SwiftData

/// Turns the business's records into `SearchDocument`s.
enum SearchDocuments {

    /// Everything one business has, for search.
    @MainActor
    static func all(businessID: UUID, context: ModelContext, includeExpenses: Bool = true) -> [SearchDocument] {
        let clients = (try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let jobs = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let contracts = (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let expenses = includeExpenses
            ? (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
            : []
        return build(clients: clients, invoices: invoices, jobs: jobs, contracts: contracts, expenses: expenses)
    }

    static func build(
        clients: [Client],
        invoices: [Invoice],
        jobs: [Job],
        contracts: [Contract],
        expenses: [Expense]
    ) -> [SearchDocument] {
        let clientNames = Dictionary(clients.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return clients.map(document)
            + invoices.map(document)
            + jobs.map { document($0, clientName: $0.clientID.flatMap { clientNames[$0] }) }
            + contracts.map(document)
            + expenses.map { document($0, clientName: $0.clientID.flatMap { clientNames[$0] }) }
    }

    static func document(_ client: Client) -> SearchDocument {
        let name = trimmed(client.name)
        let contact = [client.email, client.phone].map(trimmed).first { !$0.isEmpty }
        return SearchDocument(
            kind: .client,
            recordID: client.id,
            title: name.isEmpty ? "Unnamed client" : name,
            subtitle: join([contact ?? "No contact details", client.isArchived ? "Archived" : nil]),
            date: client.createdAt ?? .distantPast,
            terms: [client.email, client.phone, SearchEngine.digits(client.phone), client.address, client.notes]
        )
    }

    static func document(_ invoice: Invoice) -> SearchDocument {
        let isEstimate = invoice.documentType == "estimate"
        let noun = isEstimate ? "Estimate" : "Invoice"
        let number = trimmed(invoice.invoiceNumber)
        let client = trimmed(invoice.client?.name ?? "")
        let status = isEstimate ? estimateStatusLabel(invoice.estimateStatus) : InvoiceListStage(invoice).label
        let items = (invoice.items ?? []).map(\.itemDescription)
        return SearchDocument(
            kind: isEstimate ? .estimate : .invoice,
            recordID: invoice.id,
            title: number.isEmpty ? "\(noun) (no number)" : "\(noun) \(number)",
            subtitle: join([client.isEmpty ? nil : client, InvoicePaymentService.currency(invoice.totalCents), status]),
            date: invoice.issueDate,
            terms: [client, invoice.job?.title ?? "", invoice.notes, status]
                + items
                + SearchEngine.amountTerms(cents: invoice.totalCents)
        )
    }

    static func document(_ job: Job, clientName: String?) -> SearchDocument {
        let title = trimmed(job.title)
        let client = trimmed(clientName ?? "")
        let stage = jobStageLabel(job.stageRaw)
        return SearchDocument(
            kind: .job,
            recordID: job.id,
            title: title.isEmpty ? "Untitled job" : title,
            subtitle: join([client.isEmpty ? nil : client, job.startDate.formatted(date: .abbreviated, time: .omitted), stage]),
            date: job.startDate,
            terms: [client, job.locationName, job.notes, stage]
        )
    }

    static func document(_ contract: Contract) -> SearchDocument {
        let title = trimmed(contract.title)
        let client = trimmed(contract.resolvedClient?.name ?? "")
        let status = (ContractStatus(rawValue: contract.statusRaw) ?? .draft).rawValue.capitalized
        return SearchDocument(
            kind: .contract,
            recordID: contract.id,
            title: title.isEmpty ? "Untitled contract" : title,
            subtitle: join([client.isEmpty ? nil : client, status]),
            date: contract.updatedAt,
            terms: [client, contract.templateName, status]
        )
    }

    static func document(_ expense: Expense, clientName: String?) -> SearchDocument {
        let vendor = trimmed(expense.vendor)
        let category = expense.category.displayName
        return SearchDocument(
            kind: .expense,
            recordID: expense.id,
            title: vendor.isEmpty ? category : vendor,
            subtitle: join([
                InvoicePaymentService.currency(expense.amountCents),
                vendor.isEmpty ? nil : category,
                expense.date.formatted(date: .abbreviated, time: .omitted),
            ]),
            date: expense.date,
            terms: [category, expense.notes, clientName ?? ""] + SearchEngine.amountTerms(cents: expense.amountCents)
        )
    }

    // MARK: - Labels

    /// The words the Estimates list uses.
    static func estimateStatusLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "sent": return "Sent"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        default: return "Draft"
        }
    }

    static func jobStageLabel(_ raw: String) -> String {
        switch JobStage(rawValue: raw) ?? .booked {
        case .booked: return "Booked"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
