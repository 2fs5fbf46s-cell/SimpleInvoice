import XCTest
import SwiftData
import CoreGraphics
@testable import SmallBizWorkspace

final class SmallBizWorkspaceTests: XCTestCase {
    func testExample() throws {
        XCTAssertTrue(true)
    }
}

final class InvoicePDFRenderingTests: XCTestCase {
    func testLongLineItemsPaginateAndUsePreferredFileName() throws {
        let consultationScope = """
        Church Audio & Broadcast Consultation Services
        - Review the existing front-of-house mix position, wireless microphone coordination, monitor routing, stage patching, livestream feed path, and recording workflow.
        - Document recommended gain staging, routing cleanup, speaker processing, broadcast matrix sends, volunteer handoff notes, and Sunday service startup checks.
        - Provide a practical implementation roadmap covering immediate reliability fixes, medium-term training opportunities, and future equipment planning for sanctuary and overflow spaces.
        - Include follow-up notes for leadership with clear next steps, expected outcomes, and risk areas that could affect weekly services or special events.
        """

        let trainingScope = """
        Volunteer Audio Training & Development
        - Build a training plan for rotating volunteers covering console layout, mute discipline, scene recall, microphone placement, livestream balance, and troubleshooting common service issues.
        - Deliver coaching notes for new operators with repeatable checklists for rehearsal, pre-service line check, speaker handoff, worship set transitions, and post-service shutdown.
        - Create development milestones for beginner, intermediate, and lead operators so the team can grow without relying on a single engineer.
        - Include practical examples for EQ decisions, compression restraint, feedback prevention, and communication between worship leadership, tech leadership, and camera operators.
        """

        let longConsultation = Array(repeating: consultationScope, count: 12).joined(separator: "\n")
        let longTraining = Array(repeating: trainingScope, count: 12).joined(separator: "\n")
        let invoice = Invoice(
            invoiceNumber: "2026-032",
            notes: "Please review the scope and contact us with any questions.",
            thankYou: "Thank you for trusting us with your audio systems.",
            termsAndConditions: "Payment is due according to the payment terms listed above.",
            documentType: "invoice",
            items: [
                LineItem(itemDescription: longConsultation, quantity: 1, unitPrice: 250),
                LineItem(itemDescription: longTraining, quantity: 1, unitPrice: 250)
            ]
        )

        let data = InvoicePDFGenerator.makePDFData(
            invoice: invoice,
            business: BusinessSnapshot(name: "SmallBiz Audio", address: "100 Main Street", phone: "555-0100", email: "hello@example.com")
        )

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 2)
        XCTAssertEqual(InvoicePDFGenerator.preferredPDFFileName(for: invoice), "Invoice_2026-032.pdf")

        let url = try InvoicePDFGenerator.writePDFToTemporaryFile(
            data: data,
            filename: InvoicePDFGenerator.preferredPDFFileName(for: invoice)
        )
        XCTAssertEqual(url.lastPathComponent, "Invoice_2026-032.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPreferredPDFFileNameSanitizesUnsupportedCharacters() {
        let invoice = Invoice(invoiceNumber: "2026/032:Main*Room?", documentType: "invoice")
        let fileName = InvoicePDFGenerator.preferredPDFFileName(for: invoice)

        XCTAssertEqual(fileName, "Invoice_2026-032-Main-Room.pdf")
        for unsupported in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
            XCTAssertFalse(fileName.contains(unsupported))
        }
    }
}

@MainActor
final class InvoiceDuplicationAndCatalogTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Business.self,
            BusinessProfile.self,
            Client.self,
            Invoice.self,
            LineItem.self,
            CatalogItem.self,
            Contract.self,
            ClientAttachment.self,
            JobAttachment.self,
            AuditEvent.self,
            PortalIdentity.self,
            PortalSession.self,
            PortalInvite.self,
            PortalAuditEvent.self,
            EstimateDecisionRecord.self,
            ContractTemplate.self,
            Folder.self,
            FileItem.self,
            InvoiceAttachment.self,
            ContractAttachment.self,
            Job.self,
            Blockout.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testDuplicateInvoiceCopiesEditableFieldsAndResetsRuntimeFields() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let currentYear = Calendar.current.component(.year, from: .now)

        let profile = BusinessProfile(
            businessID: businessID,
            invoicePrefix: "DUP",
            nextInvoiceNumber: 7,
            lastInvoiceYear: currentYear
        )
        let client = Client(businessID: businessID, name: "Client")
        let job = Job(
            businessID: businessID,
            clientID: client.id,
            title: "Install",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600)
        )
        let item = LineItem(itemDescription: "Labor\nSetup", quantity: 2, unitPrice: 125)
        let source = Invoice(
            businessID: businessID,
            businessSnapshotData: Data("old snapshot".utf8),
            invoiceNumber: "DUP-\(currentYear)-006",
            issueDate: Date(timeIntervalSince1970: 1_000),
            dueDate: Date(timeIntervalSince1970: 1_000 + 21 * 86_400),
            paymentTerms: "Net 21",
            notes: "Original notes",
            thankYou: "Thanks",
            termsAndConditions: "Terms",
            taxRate: 0.0825,
            discountAmount: 50,
            isPaid: true,
            documentType: "invoice",
            sourceBookingRequestId: "booking-1",
            sourceEstimateId: "estimate-1",
            pdfRelativePath: "old.pdf",
            invoiceTemplateKeyOverride: "modern_clean",
            portalNeedsUpload: false,
            portalUploadInFlight: true,
            portalLastUploadedAtMs: 123,
            portalLastUploadError: "old error",
            portalLastUploadedBlobUrl: "https://example.com/old.pdf",
            portalLastUploadedHash: "hash",
            client: client,
            job: job,
            items: [item]
        )
        source.sourceBookingDepositAmountCents = 1_000
        source.sourceBookingDepositPaidAtMs = 123
        source.sourceBookingDepositInvoiceId = "deposit-1"

        context.insert(profile)
        context.insert(client)
        context.insert(job)
        context.insert(source)
        try context.save()

        let copy = try InvoiceDuplicationService.duplicate(
            invoice: source,
            profiles: [profile],
            context: context
        )

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.businessID, businessID)
        XCTAssertEqual(copy.invoiceNumber, "DUP-\(currentYear)-007")
        XCTAssertEqual(profile.nextInvoiceNumber, 8)
        XCTAssertTrue(copy.client === client)
        XCTAssertTrue(copy.job === job)
        XCTAssertEqual(copy.paymentTerms, source.paymentTerms)
        XCTAssertEqual(copy.notes, source.notes)
        XCTAssertEqual(copy.thankYou, source.thankYou)
        XCTAssertEqual(copy.termsAndConditions, source.termsAndConditions)
        XCTAssertEqual(copy.taxRate, source.taxRate)
        XCTAssertEqual(copy.discountAmount, source.discountAmount)
        XCTAssertEqual(copy.invoiceTemplateKeyOverride, source.invoiceTemplateKeyOverride)
        XCTAssertFalse(copy.isPaid)
        XCTAssertNil(copy.businessSnapshotData)
        XCTAssertEqual(copy.pdfRelativePath, "")
        XCTAssertTrue(copy.portalNeedsUpload)
        XCTAssertFalse(copy.portalUploadInFlight)
        XCTAssertNil(copy.portalLastUploadedAtMs)
        XCTAssertNil(copy.portalLastUploadError)
        XCTAssertNil(copy.portalLastUploadedBlobUrl)
        XCTAssertNil(copy.portalLastUploadedHash)
        XCTAssertNil(copy.sourceBookingRequestId)
        XCTAssertNil(copy.sourceEstimateId)
        XCTAssertNil(copy.sourceBookingDepositAmountCents)
        XCTAssertNil(copy.sourceBookingDepositPaidAtMs)
        XCTAssertNil(copy.sourceBookingDepositInvoiceId)

        let copiedItem = try XCTUnwrap(copy.items?.first)
        XCTAssertNotEqual(copiedItem.id, item.id)
        XCTAssertEqual(copiedItem.itemDescription, item.itemDescription)
        XCTAssertEqual(copiedItem.quantity, item.quantity)
        XCTAssertEqual(copiedItem.unitPrice, item.unitPrice)
        XCTAssertTrue(copiedItem.invoice === copy)
    }

    func testCatalogAutoSaveDeduplicatesByBusinessAndNormalizedName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()

        let first = try CatalogItemAutoSaveService.save(
            name: "  Labor Setup  ",
            details: "Initial",
            unitPrice: 100,
            quantity: 2,
            businessID: businessID,
            context: context
        )
        let second = try CatalogItemAutoSaveService.save(
            name: "labor   setup",
            details: "Changed",
            unitPrice: 100,
            quantity: 4,
            businessID: businessID,
            context: context
        )

        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(first?.created == true)
        XCTAssertTrue(second?.created == false)
        XCTAssertEqual(items.first?.name, "Labor Setup")
        XCTAssertEqual(items.first?.details, "Initial")
        XCTAssertEqual(items.first?.defaultQuantity, 2)
    }

    func testCatalogAutoSaveKeepsBusinessesScoped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessA = UUID()
        let businessB = UUID()

        _ = try CatalogItemAutoSaveService.save(
            name: "Consulting",
            details: "",
            unitPrice: 50,
            quantity: 1,
            businessID: businessA,
            context: context
        )
        _ = try CatalogItemAutoSaveService.save(
            name: "consulting",
            details: "",
            unitPrice: 50,
            quantity: 1,
            businessID: businessB,
            context: context
        )

        let items = try context.fetch(FetchDescriptor<CatalogItem>())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter { $0.businessID == businessA }.count, 1)
        XCTAssertEqual(items.filter { $0.businessID == businessB }.count, 1)
    }

    func testDraftInvoiceRenderingUsesLiveBusinessProfileWithoutLocking() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let profile = BusinessProfile(businessID: businessID, name: "Old Name")
        let invoice = Invoice(businessID: businessID, invoiceNumber: "INV-1", documentType: "invoice")

        context.insert(profile)
        context.insert(invoice)
        try context.save()

        let firstSnapshot = InvoicePDFService.businessSnapshotForRendering(
            invoice: invoice,
            profiles: [profile],
            context: context
        )
        XCTAssertEqual(firstSnapshot.name, "Old Name")
        XCTAssertNil(invoice.businessSnapshotData)

        profile.name = "New Name"
        try context.save()

        let updatedSnapshot = InvoicePDFService.businessSnapshotForRendering(
            invoice: invoice,
            profiles: [profile],
            context: context
        )
        XCTAssertEqual(updatedSnapshot.name, "New Name")
        XCTAssertNil(invoice.businessSnapshotData)
        XCTAssertNil(invoice.businessSnapshotLockedAt)
        XCTAssertNil(invoice.businessSnapshotLockReason)
    }

    func testSentInvoiceKeepsLockedBusinessProfileAfterProfileChange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let profile = BusinessProfile(businessID: businessID, name: "Name At Send")
        let invoice = Invoice(businessID: businessID, invoiceNumber: "INV-2", documentType: "invoice")

        context.insert(profile)
        context.insert(invoice)
        try context.save()

        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: [profile],
            context: context,
            reason: .sent,
            replaceExistingUnlockedSnapshot: true
        )

        profile.name = "Changed Later"
        try context.save()

        let renderedSnapshot = InvoicePDFService.businessSnapshotForRendering(
            invoice: invoice,
            profiles: [profile],
            context: context
        )
        XCTAssertEqual(renderedSnapshot.name, "Name At Send")
        XCTAssertEqual(invoice.businessSnapshot?.name, "Name At Send")
        XCTAssertEqual(invoice.businessSnapshotLockReason, BusinessSnapshotLockReason.sent.rawValue)
    }

    func testRefreshBusinessInfoClearsStaleDraftSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let profile = BusinessProfile(businessID: businessID, name: "Current Profile")
        let invoice = Invoice(
            businessID: businessID,
            businessSnapshotData: try JSONEncoder().encode(BusinessSnapshot(name: "Preview Name")),
            invoiceNumber: "INV-3",
            documentType: "invoice"
        )

        context.insert(profile)
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(invoice.canRefreshBusinessInfo)
        XCTAssertTrue(InvoicePDFService.refreshBusinessInfoForDraft(invoice: invoice, context: context))
        XCTAssertNil(invoice.businessSnapshotData)

        let renderedSnapshot = InvoicePDFService.businessSnapshotForRendering(
            invoice: invoice,
            profiles: [profile],
            context: context
        )
        XCTAssertEqual(renderedSnapshot.name, "Current Profile")
    }

    func testPortalUploadLockReplacesStaleDraftSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let businessID = UUID()
        let profile = BusinessProfile(businessID: businessID, name: "Portal Profile")
        let invoice = Invoice(
            businessID: businessID,
            businessSnapshotData: try JSONEncoder().encode(BusinessSnapshot(name: "Preview Name")),
            invoiceNumber: "INV-4",
            documentType: "invoice"
        )

        context.insert(profile)
        context.insert(invoice)
        try context.save()

        let lockedSnapshot = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: [profile],
            context: context,
            reason: .portal,
            replaceExistingUnlockedSnapshot: true
        )

        XCTAssertEqual(lockedSnapshot.name, "Portal Profile")
        XCTAssertEqual(invoice.businessSnapshot?.name, "Portal Profile")
        XCTAssertEqual(invoice.businessSnapshotLockReason, BusinessSnapshotLockReason.portal.rawValue)
        XCTAssertTrue(invoice.isBusinessInfoLocked)
    }
}
