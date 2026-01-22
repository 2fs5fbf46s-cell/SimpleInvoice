import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class FileItem {
    // Identity (NO unique constraint for CloudKit)
    var id: UUID = UUID()

    // Dates (default values required)
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    // Display (default values required)
    var displayName: String = ""
    var originalFileName: String = ""

    // Storage (default values required)
    var relativePath: String = ""
    var fileExtension: String = ""
    var uti: String = "public.data"
    var byteCount: Int64 = 0

    // ✅ Stable folder filter key (default required)
    var folderKey: String = ""

    // Relationship (must have inverse on Folder)
    @Relationship var folder: Folder? = nil
    
    @Relationship(inverse: \InvoiceAttachment.file) var invoiceAttachments: [InvoiceAttachment]? = nil
    @Relationship(inverse: \ContractAttachment.file) var contractAttachments: [ContractAttachment]? = nil
    @Relationship(inverse: \ClientAttachment.file) var clientAttachments: [ClientAttachment]? = nil
    @Relationship(inverse: \JobAttachment.file) var jobAttachments: [JobAttachment]? = nil
    


    init() {}

    init(
        displayName: String,
        originalFileName: String,
        relativePath: String,
        fileExtension: String,
        uti: String,
        byteCount: Int64,
        folderKey: String,
        folder: Folder? = nil
    ) {
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.uti = uti
        self.byteCount = byteCount
        self.folderKey = folderKey
        self.folder = folder
        self.updatedAt = .now
    }
}

extension FileItem {
    var utType: UTType? { UTType(uti) }
}
