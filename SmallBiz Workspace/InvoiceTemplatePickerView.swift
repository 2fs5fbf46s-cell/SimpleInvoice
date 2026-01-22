//
//  InvoiceTemplatePickerView.swift
//  SimpleInvoice (or SmallBiz Workspace)
//

import SwiftUI

struct InvoiceTemplatePickerView: View {
    let templates: [InvoiceTemplate]
    let onUse: (InvoiceTemplate) -> Void

    var body: some View {
        List {
            ForEach(templates) { t in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t.title)
                            .font(.headline)

                        Text(t.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            // ✅ Let the parent handle dismiss + navigation
                            onUse(t)
                        } label: {
                            Label("Use This Template", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent)
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
