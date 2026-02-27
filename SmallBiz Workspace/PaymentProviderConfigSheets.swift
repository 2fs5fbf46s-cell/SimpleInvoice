import SwiftUI

private func normalizeURLInput(_ raw: String) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
        return value
    }
    return "https://\(value)"
}

private func normalizeCashAppInputSheet(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
        return trimmed
    }
    let handle = trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed
    guard !handle.isEmpty else { return nil }
    return "https://cash.app/$\(handle)"
}

private func normalizeVenmoInputSheet(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
        return trimmed
    }
    let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    guard !handle.isEmpty else { return nil }
    return "https://venmo.com/u/\(handle)"
}

private func sanitizeLast4Input(_ raw: String) -> String {
    String(raw.filter(\.isNumber).suffix(4))
}

private struct PaymentPreviewBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct SquareConfigSheet: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var link: String

    init(initialLink: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _link = State(initialValue: initialLink)
    }

    private var normalized: String? { normalizeURLInput(link) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add your Square payment link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://square.link/...", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                PaymentPreviewBlock(
                    title: "Customers will pay using",
                    value: normalized ?? "Add a valid Square link to preview."
                )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Configure Square")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(normalized) }
                        .disabled(normalized == nil)
                }
            }
        }
    }
}

struct CashAppConfigSheet: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var value: String

    init(initialValue: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _value = State(initialValue: initialValue)
    }

    private var normalized: String? { normalizeCashAppInputSheet(value) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add your Cash App handle or direct URL.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("$handle or URL", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                PaymentPreviewBlock(
                    title: "Customers will pay using",
                    value: normalized ?? "Add a handle or URL to preview."
                )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Configure Cash App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(normalized) }
                        .disabled(normalized == nil)
                }
            }
        }
    }
}

struct VenmoConfigSheet: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var value: String

    init(initialValue: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _value = State(initialValue: initialValue)
    }

    private var normalized: String? { normalizeVenmoInputSheet(value) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add your Venmo handle or direct URL.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("@handle or URL", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                PaymentPreviewBlock(
                    title: "Customers will pay using",
                    value: normalized ?? "Add a handle or URL to preview."
                )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Configure Venmo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(normalized) }
                        .disabled(normalized == nil)
                }
            }
        }
    }
}

struct ACHConfigSheet: View {
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var instructions: String
    @State private var last4: String

    init(initialInstructions: String, initialLast4: String, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _instructions = State(initialValue: initialInstructions)
        _last4 = State(initialValue: initialLast4)
    }

    private var cleanedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedLast4: String {
        sanitizeLast4Input(last4)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add bank transfer instructions for customers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $instructions)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                TextField("Account Last 4 (optional)", text: $last4)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: last4) { _, newValue in
                        last4 = sanitizeLast4Input(newValue)
                    }

                PaymentPreviewBlock(
                    title: "Customers will see",
                    value: cleanedInstructions.isEmpty
                        ? "Add instructions to preview."
                        : "Bank transfer instructions:\n\(cleanedInstructions)"
                )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Configure ACH")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(cleanedInstructions, cleanedLast4)
                    }
                    .disabled(cleanedInstructions.isEmpty)
                }
            }
        }
    }
}

struct PayPalFallbackConfigSheet: View {
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var value: String

    init(initialValue: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _value = State(initialValue: initialValue)
    }

    private var normalized: String? { normalizeURLInput(value) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add an optional PayPal.me fallback link for manual reconciliation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://paypal.me/yourname", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                PaymentPreviewBlock(
                    title: "Customers will pay using",
                    value: normalized ?? "No fallback link configured."
                )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Configure PayPal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(normalized) }
                }
            }
        }
    }
}
