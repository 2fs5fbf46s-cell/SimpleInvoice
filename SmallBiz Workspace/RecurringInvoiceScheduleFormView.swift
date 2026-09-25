import OSLog
import SwiftUI
import SwiftData

/// Add/edit form for a recurring invoice schedule. Same dual-mode shape as
/// `ExpenseFormView`: pushed for an existing schedule (auto-saves as you
/// type, syncing each change to the backend so the generation cron sees it),
/// or presented in a sheet for a freshly-inserted draft with explicit
/// Save/Cancel.
struct RecurringInvoiceScheduleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var schedule: RecurringInvoiceSchedule
    let isDraft: Bool
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Query private var clients: [Client]

    @State private var syncError: String? = nil
    @State private var isSyncing = false

    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    init(
        schedule: RecurringInvoiceSchedule,
        isDraft: Bool,
        onSave: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.schedule = schedule
        self.isDraft = isDraft
        self.onSave = onSave
        self.onCancel = onCancel

        let businessID = schedule.businessID
        _clients = Query(
            filter: #Predicate<Client> { $0.businessID == businessID && $0.portalEnabled },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
    }

    private var isValid: Bool {
        !clients.isEmpty
            && schedule.lineItems.contains {
                !$0.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.unitPrice > 0
            }
    }

    var body: some View {
        Form {
            if clients.isEmpty {
                Section {
                    Text("This business has no clients with Client Portal enabled yet. Enable it on a client's profile first.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Client") {
                Picker("Client", selection: $schedule.clientID) {
                    ForEach(clients.filter { !$0.isArchived || $0.id == schedule.clientID }) { client in
                        Text(client.name.isEmpty ? "Client" : client.name).tag(client.id)
                    }
                }
                .onChange(of: schedule.clientID) { _, _ in saveIfEditing() }

                Toggle("Active", isOn: $schedule.active)
                    .onChange(of: schedule.active) { _, _ in saveIfEditing() }
            }

            Section("Schedule") {
                Picker("Repeats", selection: $schedule.cadence) {
                    ForEach(RecurringCadence.allCases) { cadence in
                        Text(cadence.displayName).tag(cadence)
                    }
                }
                .onChange(of: schedule.cadence) { _, _ in saveIfEditing() }

                DatePicker("Next Invoice", selection: $schedule.nextRunAt, displayedComponents: .date)
                    .onChange(of: schedule.nextRunAt) { _, _ in saveIfEditing() }

                Stepper("Due \(schedule.netDays) days after", value: $schedule.netDays, in: 0...90)
                    .onChange(of: schedule.netDays) { _, _ in saveIfEditing() }
            }

            Section("Line Items") {
                ForEach(Array(schedule.lineItems.enumerated()), id: \.element.id) { index, _ in
                    lineItemRow(at: index)
                }
                .onDelete(perform: removeLineItems)

                Button {
                    var items = schedule.lineItems
                    items.append(RecurringScheduleLineItem())
                    schedule.lineItems = items
                    saveIfEditing()
                } label: {
                    Label("Add Line Item", systemImage: "plus")
                }
            }

            Section("Pricing") {
                HStack {
                    Text("Tax Rate")
                    Spacer()
                    TextField("0", value: $schedule.taxRatePercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: schedule.taxRatePercent) { _, _ in saveIfEditing() }
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Discount")
                    Spacer()
                    TextField(
                        "$0.00",
                        value: $schedule.discountAmount,
                        format: .currency(code: currencyCode)
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: schedule.discountAmount) { _, _ in saveIfEditing() }
                }

                summaryRow(label: "Subtotal", value: schedule.subtotal)
                summaryRow(label: "Tax", value: schedule.taxAmount)
                summaryRow(label: "Total per invoice", value: schedule.total, emphasized: true)
            }

            if isSyncing {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isDraft ? "New Recurring Invoice" : "Recurring Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            if isDraft {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try modelContext.save()
                            Haptics.success()
                            onSave?()
                            syncToBackend()
                        } catch {
                            Haptics.error()
                            SBWLog.ui.problem("Failed to save new schedule: \(error)")
                        }
                    }
                    .disabled(!isValid)
                }
            } else {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        let scheduleID = schedule.id
                        Task { try? await PortalBackend.shared.deleteRecurringSchedule(scheduleId: scheduleID) }
                        modelContext.delete(schedule)
                        do { try modelContext.save() } catch {
                            SBWLog.ui.problem("Failed to save after deleting schedule: \(error)")
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .alert("Sync Failed", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK", role: .cancel) { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
    }

    private func lineItemRow(at index: Int) -> some View {
        let items = schedule.lineItems
        guard index < items.count else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                TextField("Description", text: Binding(
                    get: { schedule.lineItems[safe: index]?.itemDescription ?? "" },
                    set: { newValue in updateLineItem(at: index) { $0.itemDescription = newValue } }
                ))

                HStack {
                    Stepper(
                        "Qty \(items[index].quantity.formatted())",
                        value: Binding(
                            get: { schedule.lineItems[safe: index]?.quantity ?? 1 },
                            set: { newValue in updateLineItem(at: index) { $0.quantity = newValue } }
                        ),
                        in: 0...10000,
                        step: 1
                    )

                    Spacer()

                    TextField(
                        "$0.00",
                        value: Binding(
                            get: { schedule.lineItems[safe: index]?.unitPrice ?? 0 },
                            set: { newValue in updateLineItem(at: index) { $0.unitPrice = newValue } }
                        ),
                        format: .currency(code: currencyCode)
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
                }
            }
            .padding(.vertical, 2)
        )
    }

    private func updateLineItem(at index: Int, _ mutate: (inout RecurringScheduleLineItem) -> Void) {
        var items = schedule.lineItems
        guard index < items.count else { return }
        var item = items[index]
        mutate(&item)
        items[index] = item
        schedule.lineItems = items
        saveIfEditing()
    }

    private func removeLineItems(at offsets: IndexSet) {
        var items = schedule.lineItems
        items.remove(atOffsets: offsets)
        schedule.lineItems = items
        saveIfEditing()
    }

    private func summaryRow(label: String, value: Double, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer()
            Text(value.formatted(.currency(code: currencyCode)))
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .monospacedDigit()
        }
    }

    private func saveIfEditing() {
        guard !isDraft else { return }
        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save schedule edit: \(error)") }
        syncToBackend()
    }

    private func syncToBackend() {
        guard let client = clients.first(where: { $0.id == schedule.clientID }) else { return }
        isSyncing = true
        Task {
            do {
                try await PortalBackend.shared.upsertRecurringSchedule(schedule, clientEmail: client.email)
            } catch {
                syncError = "This schedule is saved on your device but couldn't reach the server, so it won't generate invoices until it syncs. \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// Compared by what it shows; callbacks and bindings are ignored.
extension RecurringInvoiceScheduleFormView: Equatable {
    static func == (lhs: RecurringInvoiceScheduleFormView, rhs: RecurringInvoiceScheduleFormView) -> Bool {
        lhs.schedule.persistentModelID == rhs.schedule.persistentModelID
            && lhs.isDraft == rhs.isDraft
    }
}
