import SwiftUI

struct InvoiceTemplatePickerSheet: View {
    enum Mode {
        case businessDefault
        case invoiceOverride
        case clientPreferred

        var navigationTitle: String {
            switch self {
            case .businessDefault:
                return "Default Invoice Template"
            case .invoiceOverride:
                return "Invoice Template"
            case .clientPreferred:
                return "Preferred Invoice Template"
            }
        }

        var templateScopeCopy: String {
            switch self {
            case .businessDefault:
                return "Applies to all new invoices"
            case .invoiceOverride:
                return "Applies to this invoice only"
            case .clientPreferred:
                return "Applies to this client's new invoices"
            }
        }

        var effectiveLabel: String {
            switch self {
            case .businessDefault:
                return "Current default"
            case .invoiceOverride:
                return "Current effective template"
            case .clientPreferred:
                return "Current effective template"
            }
        }
    }

    let mode: Mode
    let businessDefault: InvoiceTemplateKey
    let currentEffective: InvoiceTemplateKey
    let currentSelection: InvoiceTemplateKey?
    let onSelectTemplate: (InvoiceTemplateKey) -> Void
    let onUseBusinessDefault: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var showsDefaultRow: Bool {
        mode != .businessDefault
    }

    private var hasCustomSelection: Bool {
        currentSelection != nil
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("\(mode.effectiveLabel): \(currentEffective.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if mode == .invoiceOverride, hasCustomSelection {
                        Text("Override Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.16))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            if showsDefaultRow {
                Section {
                    Button {
                        onUseBusinessDefault()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            InvoiceTemplateThumbnail(templateKey: businessDefault)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default (Business)")
                                    .foregroundStyle(.primary)
                                Text("Applies to all new invoices (unless overridden)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Current business default: \(businessDefault.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if currentSelection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Templates") {
                ForEach(InvoiceTemplateKey.allCases) { key in
                    Button {
                        onSelectTemplate(key)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            InvoiceTemplateThumbnail(templateKey: key)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.displayName)
                                    .foregroundStyle(.primary)
                                Text(key.shortDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(mode.templateScopeCopy)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if key == currentEffective {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if mode == .invoiceOverride, hasCustomSelection {
                Section {
                    Button("Clear Override", role: .destructive) {
                        onUseBusinessDefault()
                        dismiss()
                    }
                }
            }

            if mode == .clientPreferred, hasCustomSelection {
                Section {
                    Button("Clear Client Preference", role: .destructive) {
                        onUseBusinessDefault()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
