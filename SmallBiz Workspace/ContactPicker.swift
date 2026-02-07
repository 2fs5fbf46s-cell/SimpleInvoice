import SwiftUI
import Contacts
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onSelect: (CNContact) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private var isPresented: Binding<Bool>
        private let onSelect: (CNContact) -> Void
        private let onCancel: () -> Void

        init(isPresented: Binding<Bool>, onSelect: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.isPresented = isPresented
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
            isPresented.wrappedValue = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
            isPresented.wrappedValue = false
        }
    }
}

struct ContactImportFields {
    var name: String
    var email: String
    var phone: String
    var address: String
}

enum ContactImportMapper {
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedPhone(_ phone: String) -> String {
        phone.filter { $0.isNumber }
    }

    static func fields(from contact: CNContact) -> ContactImportFields {
        let fullName = "\(contact.givenName) \(contact.familyName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let orgName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = !fullName.isEmpty ? fullName : (!orgName.isEmpty ? orgName : "New Client")

        let email = contact.emailAddresses.first?.value as String? ?? ""
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        let address = formattedAddress(from: contact.postalAddresses.first?.value)

        return ContactImportFields(
            name: name,
            email: email,
            phone: phone,
            address: address
        )
    }

    static func apply(contact: CNContact, to client: Client) {
        let f = fields(from: contact)
        client.name = f.name
        client.email = f.email
        client.phone = f.phone
        client.address = f.address
    }

    static func findDuplicateClient(
        in clients: [Client],
        fields: ContactImportFields,
        businessID: UUID?
    ) -> Client? {
        let email = normalizedEmail(fields.email)
        let phone = normalizedPhone(fields.phone)

        return clients.first { client in
            if let businessID, client.businessID != businessID {
                return false
            }

            let clientEmail = normalizedEmail(client.email)
            let clientPhone = normalizedPhone(client.phone)

            let emailMatch = !email.isEmpty && email == clientEmail
            let phoneMatch = !phone.isEmpty && phone == clientPhone
            return emailMatch || phoneMatch
        }
    }

    private static func formattedAddress(from postal: CNPostalAddress?) -> String {
        guard let postal else { return "" }

        let street = postal.street.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = postal.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = postal.state.trimmingCharacters(in: .whitespacesAndNewlines)
        let postalCode = postal.postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = postal.country.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if !street.isEmpty { lines.append(street) }

        let cityLine = [city, state, postalCode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .replacingOccurrences(of: ", ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cityLine.isEmpty { lines.append(cityLine) }

        if !country.isEmpty { lines.append(country) }

        return lines.joined(separator: "\n")
    }
}
