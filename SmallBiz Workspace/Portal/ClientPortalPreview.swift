import SwiftUI
import SwiftData

struct ClientPortalPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore



    // Token entry + validation
    @State private var tokenInput: String = ""
    @State private var session: PortalSession? = nil
    @State private var errorText: String? = nil

    // Data
    @State private var invoices: [Invoice] = []
    @State private var contracts: [Contract] = []

    // Signing
    @State private var signContractItem: Contract? = nil

    // PDF preview
    @State private var pdfPreview: IdentifiableURL? = nil

    var body: some View {
        List {
            sessionSection

            if let session {
                estimatesSection(for: session)
                invoicesSection(for: session)
                contractsSection(for: session)
            }
        }
        .navigationTitle("Client Portal (Preview)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pdfPreview) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: $signContractItem) { contract in
            Group {
                if let s = session {
                    PortalContractSignView(
                        portal: PortalService(modelContext: modelContext),
                        session: s,
                        contract: contract
                    )
                } else {
                    EmptyView()
                }
            }
        }
        .onChange(of: signContractItem) { _, newValue in
            // refresh after signing sheet closes
            if newValue == nil, let s = session {
                loadClientData(clientID: s.clientID, businessID: s.businessID)
            }
        }
    }

    // MARK: - Sections

    private var sessionSection: some View {
        Section("Portal Session") {
            TextField("Paste session token", text: $tokenInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Validate Token") { validateToken() }

            if let activeID = activeBiz.activeBusinessID {
                Text("Active Business: \(activeID.uuidString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let session {
                Text("✅ Session active")
                    .foregroundStyle(.green)
                Text("Client ID: \(session.clientID.uuidString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
            }
        }
    }

    private func estimatesSection(for session: PortalSession) -> some View {
        Section("Estimates") {
            let estimates = invoices.filter { $0.documentType == "estimate" }

            if estimates.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(estimates) { inv in
                    HStack(alignment: .top) {
                        invoiceRow(inv)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                logView(
                                    event: "estimate.viewed",
                                    session: session,
                                    entityID: inv.id,
                                    entityType: "Invoice"
                                )
                            }

                        Spacer()

                        Button("PDF") { previewInvoicePDF(inv, session: session) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        if inv.estimateStatus != "accepted" && inv.estimateStatus != "declined" {
                            Button("Accept") { acceptEstimate(inv, session: session) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func invoicesSection(for session: PortalSession) -> some View {
        Section("Invoices") {
            let realInvoices = invoices.filter { $0.documentType == "invoice" }

            if realInvoices.isEmpty {
                ContentUnavailableView(
                    "No Invoices",
                    systemImage: "doc.text",
                    description: Text("Invoices shared in the portal will appear here.")
                )
            } else {
                ForEach(realInvoices) { inv in
                    HStack(alignment: .top) {
                        invoiceRow(inv)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                logView(
                                    event: "invoice.viewed",
                                    session: session,
                                    entityID: inv.id,
                                    entityType: "Invoice"
                                )
                            }

                        Spacer()

                        Button("PDF") { previewInvoicePDF(inv, session: session) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func contractsSection(for session: PortalSession) -> some View {
        Section("Contracts") {
            if contracts.isEmpty {
                ContentUnavailableView(
                    "No Contracts",
                    systemImage: "doc.plaintext",
                    description: Text("Contracts shared in the portal will appear here.")
                )
            } else {
                ForEach(contracts) { c in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title.isEmpty ? "Contract" : c.title)
                                .font(.headline)

                            Text(c.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let inv = c.invoice {
                                Text("Invoice \(inv.invoiceNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let est = c.estimate {
                                Text("Estimate \(est.invoiceNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let job = c.job {
                                Text("Job: \(job.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("PDF") { previewContractPDF(c, session: session) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        Button("Sign") { signContractItem = c }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(c.statusRaw != ContractStatus.sent.rawValue)
                    }
                }
            }
        }
    }

    // MARK: - Token / data

    private func validateToken() {
        errorText = nil

        let raw = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorText = "Paste a session token first."
            return
        }

        do {
            let service = PortalService(modelContext: modelContext)
            guard let validated = try service.validate(rawToken: raw) else {
                errorText = "Token invalid, expired, or revoked."
                session = nil
                invoices = []
                contracts = []
                return
            }

            // ✅ Option A: business-scoped portal admin page
            if let activeID = activeBiz.activeBusinessID, validated.businessID != activeID {
                errorText = "This token belongs to a different business. Switch to that business to view it."
                session = nil
                invoices = []
                contracts = []
                return
            }

            session = validated
            loadClientData(clientID: validated.clientID, businessID: validated.businessID)
        } catch {
            errorText = error.localizedDescription
            session = nil
            invoices = []
            contracts = []
        }
    }

    /// contract.client → invoice.client → estimate.client → job.clientID
    private func resolvedClientID(for contract: Contract) -> UUID? {
        if let id = contract.client?.id { return id }
        if let id = contract.invoice?.client?.id { return id }
        if let id = contract.estimate?.client?.id { return id }
        if let id = contract.job?.clientID { return id }
        return nil
    }

    private func repairInvoiceBusinessIDs(clientID: UUID, businessID: UUID) {
        do {
            let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
            var changed = 0

            for inv in allInvoices {
                guard inv.client?.id == clientID else { continue }
                if inv.businessID != businessID {
                    inv.businessID = businessID
                    changed += 1
                }
            }

            if changed > 0 { try modelContext.save() }
        } catch {
            print("repairInvoiceBusinessIDs error: \(error)")
        }
    }

    private func repairContractBusinessIDs(clientID: UUID, businessID: UUID) {
        do {
            let allContracts = try modelContext.fetch(FetchDescriptor<Contract>())
            var changed = 0

            for c in allContracts {
                guard resolvedClientID(for: c) == clientID else { continue }
                let inferredBiz = c.invoice?.businessID ?? c.estimate?.businessID ?? c.job?.businessID
                guard let inferredBiz else { continue }

                if inferredBiz == businessID && c.businessID != businessID {
                    c.businessID = businessID
                    changed += 1
                }
            }

            if changed > 0 { try modelContext.save() }
        } catch {
            print("repairContractBusinessIDs error: \(error)")
        }
    }

    private func loadClientData(clientID: UUID, businessID: UUID) {
        do {
            repairContractBusinessIDs(clientID: clientID, businessID: businessID)
            repairInvoiceBusinessIDs(clientID: clientID, businessID: businessID)

            let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
            invoices = allInvoices
                .filter { $0.client?.id == clientID && $0.businessID == businessID }
                .sorted { $0.issueDate > $1.issueDate }

            let allContracts = try modelContext.fetch(FetchDescriptor<Contract>())
            contracts = allContracts
                .filter { c in
                    guard c.businessID == businessID else { return false }
                    return resolvedClientID(for: c) == clientID
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorText = error.localizedDescription
        }
        
    }
    

    // MARK: - Actions / PDF / Audit (unchanged from your working version)

    private func acceptEstimate(_ inv: Invoice, session: PortalSession) {
        do {
            let service = PortalService(modelContext: modelContext)
            _ = try service.acceptEstimateFromPortal(estimateID: inv.id, session: session)
            loadClientData(clientID: session.clientID, businessID: session.businessID)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func previewContractPDF(_ contract: Contract, session: PortalSession) {
        do {
            let biz = businessProfile(for: session.businessID)
            let url = try PortalContractPDFBuilder.buildContractPDF(contract: contract, business: biz)
            pdfPreview = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func previewInvoicePDF(_ inv: Invoice, session: PortalSession) {
        do {
            let profiles = fetchProfiles()
            let pdfData = InvoicePDFService.makePDFData(
                invoice: inv,
                profiles: profiles,
                context: modelContext,
                businesses: fetchBusinesses()
            )
            let prefix = (inv.documentType == "estimate") ? "Estimate" : "Invoice"
            let safeNumber = inv.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackID = String(describing: inv.id)
            let namePart = safeNumber.isEmpty ? String(fallbackID.suffix(8)) : safeNumber
            let filename = "\(prefix)-\(namePart)"
            let url = try InvoicePDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
            pdfPreview = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func logView(event: String, session: PortalSession, entityID: UUID, entityType: String) {
        let service = PortalService(modelContext: modelContext)
        service.log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: event,
            entityType: entityType,
            entityID: entityID
        )
    }

    private func invoiceRow(_ inv: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(inv.documentType.capitalized) \(inv.invoiceNumber)")
                .font(.headline)

            Text(invoiceSubtitle(inv))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func invoiceSubtitle(_ inv: Invoice) -> String {
        let date = inv.issueDate.formatted(date: .abbreviated, time: .omitted)
        let amount = inv.total.asCurrency

        if inv.documentType == "estimate" {
            return "\(inv.estimateStatus) • \(date) • \(amount)"
        } else {
            return "\(inv.isPaid ? "paid" : "unpaid") • \(date) • \(amount)"
        }
    }
    private func businessProfile(for businessID: UUID) -> BusinessProfile? {
        do {
            // CloudKit-safe: fetch all and filter in-memory
            let all = try modelContext.fetch(FetchDescriptor<BusinessProfile>())
            return all.first(where: { $0.businessID == businessID })
        } catch {
            print("businessProfile fetch error: \(error)")
            return nil
        }
    }

    private func fetchProfiles() -> [BusinessProfile] {
        do {
            return try modelContext.fetch(FetchDescriptor<BusinessProfile>())
        } catch {
            print("profiles fetch error: \(error)")
            return []
        }
    }

    private func fetchBusinesses() -> [Business] {
        do {
            return try modelContext.fetch(FetchDescriptor<Business>())
        } catch {
            print("business fetch error: \(error)")
            return []
        }
    }

}

// MARK: - Currency helper

private extension Double {
    var asCurrency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
}
