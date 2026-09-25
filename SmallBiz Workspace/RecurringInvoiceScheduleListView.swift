import OSLog
import SwiftUI
import SwiftData

struct RecurringInvoiceScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var schedules: [RecurringInvoiceSchedule]
    @Query private var clients: [Client]
    @Query private var businesses: [Business]

    @State private var selectedSchedule: RecurringInvoiceSchedule? = nil
    @State private var draftSaved = false
    @State private var showingNewSchedule = false
    @State private var newScheduleDraft: RecurringInvoiceSchedule? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _schedules = Query(
                filter: #Predicate<RecurringInvoiceSchedule> { $0.businessID == businessID },
                sort: [SortDescriptor(\RecurringInvoiceSchedule.nextRunAt, order: .forward)]
            )
            _clients = Query(
                filter: #Predicate<Client> { $0.businessID == businessID },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )
        } else {
            _schedules = Query(sort: [SortDescriptor(\RecurringInvoiceSchedule.nextRunAt, order: .forward)])
            _clients = Query(sort: [SortDescriptor(\Client.name, order: .forward)])
        }
        _businesses = Query()
    }

    private var effectiveBusinessID: UUID? { businessID }

    private var currencyCode: String {
        InsightsCurrency.normalizedCode(businesses.first(where: { $0.id == effectiveBusinessID })?.currencyCode) ?? "USD"
    }

    private var portalEnabledClients: [Client] {
        clients.filter { $0.portalEnabled }
    }

    private var scopedSchedules: [RecurringInvoiceSchedule] {
        schedules.scoped(to: effectiveBusinessID)
    }

    private func clientName(for schedule: RecurringInvoiceSchedule) -> String {
        let name = clients.first(where: { $0.id == schedule.clientID })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty ?? true) ? "Client" : name!
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Recurring Invoices")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            Haptics.lightTap()
                            addScheduleAndOpenSheet()
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brand.opacity(0.2)))
                        }
                        .disabled(portalEnabledClients.isEmpty)
                    }
                }

                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view recurring invoices.")
                    )
                } else if portalEnabledClients.isEmpty {
                    SBWEmptyState(
                        title: "No Portal Clients Yet",
                        message: "Recurring invoices are sent through the Client Portal, so a client needs it enabled first — turn it on from their profile.",
                        systemImage: "person.2.badge.gearshape"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if scopedSchedules.isEmpty {
                    SBWEmptyState(
                        title: "No Recurring Invoices",
                        message: "Set one up here, or open an existing invoice and choose Make Recurring.",
                        systemImage: "arrow.triangle.2.circlepath",
                        actionTitle: "Add Schedule",
                        action: { addScheduleAndOpenSheet() }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(scopedSchedules) { schedule in
                        Button {
                            selectedSchedule = schedule
                        } label: {
                            scheduleRow(schedule)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteSchedules)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Recurring Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $selectedSchedule) { schedule in
            RecurringInvoiceScheduleFormView(schedule: schedule, isDraft: false)
        }
        .sheet(isPresented: $showingNewSchedule, onDismiss: {
            // Swiped away without Save: the draft was left in the list,
            // never uploaded, so it looked set up but never billed.
            if let draft = newScheduleDraft, !draftSaved { modelContext.delete(draft); try? modelContext.save() }
            newScheduleDraft = nil
            draftSaved = false
        }) {
            NavigationStack {
                if let newScheduleDraft {
                    RecurringInvoiceScheduleFormView(schedule: newScheduleDraft, isDraft: true) {
                        draftSaved = true
                        showingNewSchedule = false
                    } onCancel: {
                        showingNewSchedule = false
                    }
                } else {
                    ProgressView("Loading…")
                        .navigationTitle("New Schedule")
                }
            }
            .presentationDetents([.large])
        }
    }

    private func scheduleRow(_ schedule: RecurringInvoiceSchedule) -> some View {
        let amount = schedule.total.formatted(.currency(code: currencyCode))
        let nextRun = schedule.nextRunAt.formatted(date: .abbreviated, time: .omitted)
        let subtitle = "\(schedule.cadence.displayName) \u{2022} Next \(nextRun)"

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Requests"))
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)
            .opacity(schedule.active ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 4) {
                Text(clientName(for: schedule))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(schedule.active ? subtitle : "Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
        .opacity(schedule.active ? 1 : 0.6)
    }

    private func addScheduleAndOpenSheet() {
        guard let bizID = effectiveBusinessID, let firstClient = portalEnabledClients.first else {
            SBWLog.ui.problem("❌ No active business or portal-enabled client for a new recurring schedule")
            return
        }

        let schedule = RecurringInvoiceSchedule(businessID: bizID, clientID: firstClient.id)
        schedule.lineItems = [RecurringScheduleLineItem()]

        modelContext.insert(schedule)
        newScheduleDraft = schedule
        showingNewSchedule = true

        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save new schedule draft: \(error)") }
        Haptics.lightTap()
    }

    private func deleteSchedules(at offsets: IndexSet) {
        let toDelete: [RecurringInvoiceSchedule] = offsets.compactMap { idx -> RecurringInvoiceSchedule? in
            guard idx < scopedSchedules.count else { return nil }
            return scopedSchedules[idx]
        }

        for schedule in toDelete {
            RecurringScheduleSync.delete(schedule, context: modelContext)
        }
        Haptics.success()
    }
}
