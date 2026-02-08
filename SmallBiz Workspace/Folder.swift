import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()
    var folderKey: String = ""

    var name: String = ""
    var relativePath: String = ""
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    var parentFolderID: UUID? = nil
    
    @Relationship(inverse: \FileItem.folder) var fileItems: [FileItem]? = nil


    init(
        id: UUID = Foundation.UUID(),
        businessID: UUID,
        folderKey: String = "",
        name: String,
        relativePath: String,
        parentFolderID: UUID? = nil,
        createdAt: Date = Foundation.Date(),
        updatedAt: Date = Foundation.Date()
    ) {
        self.id = id
        self.businessID = businessID
        self.folderKey = folderKey
        self.name = name
        self.relativePath = relativePath
        self.parentFolderID = parentFolderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
