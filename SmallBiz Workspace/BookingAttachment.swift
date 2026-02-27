import Foundation
import SwiftData

@Model
final class BookingAttachment {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()

    var bookingKey: String = ""   // booking request id
    var fileKey: String = ""      // file.id.uuidString

    @Relationship var file: FileItem? = nil

    init() {}

    init(bookingKey: String, file: FileItem) {
        self.bookingKey = bookingKey
        self.file = file
        self.fileKey = file.id.uuidString
        self.createdAt = Foundation.Date()
    }
}
