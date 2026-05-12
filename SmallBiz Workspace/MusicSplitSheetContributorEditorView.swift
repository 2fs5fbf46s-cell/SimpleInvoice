import SwiftUI

struct MusicSplitSheetContributorEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var contributor: MusicSplitSheetContributor
    let onSave: (MusicSplitSheetContributor) -> Void
    let onCancel: () -> Void

    init(
        contributor: MusicSplitSheetContributor,
        onSave: @escaping (MusicSplitSheetContributor) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _contributor = State(initialValue: contributor)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            Form {
                Section("Identity") {
                    TextField("Legal name", text: $contributor.legalName)
                    TextField("Stage name / company", text: $contributor.stageNameOrCompany)

                    Picker("Role", selection: $contributor.role) {
                        ForEach(MusicSplitSheetContributor.roles, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                }

                Section("Contact") {
                    TextField("Email", text: $contributor.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $contributor.phone)
                        .keyboardType(.phonePad)
                }

                Section("Publishing") {
                    TextField("PRO affiliation", text: $contributor.proAffiliation)
                    TextField("IPI / CAE number", text: $contributor.ipiCaeNumber)
                    TextField("Publisher name", text: $contributor.publisherName)
                    MusicSplitSheetPercentField(title: "Writer Share", value: $contributor.writerSharePercent)
                    MusicSplitSheetPercentField(title: "Publishing Share", value: $contributor.publishingSharePercent)
                }

                Section("Master") {
                    MusicSplitSheetPercentField(title: "Master Ownership", value: $contributor.masterOwnershipPercent)
                    MusicSplitSheetPercentField(title: "Producer Points", value: $contributor.producerPointsPercent)
                    TextField("Royalty notes", text: $contributor.royaltyNotes, axis: .vertical)
                }

                Section("Work-for-Hire / Buyout") {
                    Toggle("Work-for-hire", isOn: $contributor.isWorkForHire)
                    TextField("Flat fee amount", text: $contributor.flatFeeAmount)
                        .keyboardType(.decimalPad)
                    TextField("Flat fee paid date", text: $contributor.flatFeePaidDate)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contributor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(contributor)
                    dismiss()
                }
            }
        }
    }
}

struct MusicSplitSheetPercentField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 96)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }
}
