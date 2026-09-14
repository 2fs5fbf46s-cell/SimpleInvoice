import OSLog
import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query private var expenses: [Expense]
    @Query private var businesses: [Business]

    @State private var searchText: String = ""
    @State private var selectedExpense: Expense? = nil
    @State private var filter: Filter = .all

    @State private var showingNewExpense = false
    @State private var newExpenseDraft: Expense? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _expenses = Query(
                filter: #Predicate<Expense> { expense in
                    expense.businessID == businessID
                },
                sort: [SortDescriptor(\Expense.date, order: .reverse)]
            )
        } else {
            _expenses = Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
        }
        _businesses = Query()
    }

    private var effectiveBusinessID: UUID? {
        businessID
    }

    private var currencyCode: String {
        InsightsCurrency.normalizedCode(businesses.first(where: { $0.id == effectiveBusinessID })?.currencyCode) ?? "USD"
    }

    private enum Filter: Hashable, Identifiable {
        case all
        case category(ExpenseCategory)

        var id: String {
            switch self {
            case .all: return "all"
            case .category(let c): return c.rawValue
            }
        }

        var title: String {
            switch self {
            case .all: return "All"
            case .category(let c): return c.displayName
            }
        }

        static var options: [Filter] {
            [.all] + ExpenseCategory.allCases.map(Filter.category)
        }
    }

    // MARK: - Scoped expenses (active business)

    private var scopedExpenses: [Expense] {
        expenses.scoped(to: effectiveBusinessID)
    }

    private var filteredExpenses: [Expense] {
        let byFilter: [Expense]
        switch filter {
        case .all:
            byFilter = scopedExpenses
        case .category(let category):
            byFilter = scopedExpenses.filter { $0.category == category }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return byFilter }

        return byFilter.filter { expense in
            if expense.vendor.localizedCaseInsensitiveContains(query) { return true }
            if expense.notes.localizedCaseInsensitiveContains(query) { return true }
            if expense.category.displayName.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    private var filteredTotalCents: Int {
        filteredExpenses.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search expenses", text: $searchText)
                            .textInputAutocapitalization(.never)

                        Button {
                            Haptics.lightTap()
                            addExpenseAndOpenSheet()
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.2)))
                        }
                    }
                }

                Section {
                    SBWFilterChips(
                        options: Filter.options,
                        title: { $0.title },
                        selection: $filter
                    )
                }

                if !filteredExpenses.isEmpty {
                    Section {
                        HStack {
                            Text("\(filteredExpenses.count) expense\(filteredExpenses.count == 1 ? "" : "s")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(InsightsCurrency.string(cents: filteredTotalCents, code: currencyCode))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view expenses.")
                    )
                } else if filteredExpenses.isEmpty {
                    let isFiltered = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || filter != .all
                    SBWEmptyState(
                        title: scopedExpenses.isEmpty ? "No Expenses Yet" : "No Results",
                        message: scopedExpenses.isEmpty
                            ? SBWEmptyStateCopy.message(noun: "expense", pluralNoun: "expenses", isFiltered: false)
                            : SBWEmptyStateCopy.message(noun: "expense", pluralNoun: "expenses", isFiltered: true),
                        systemImage: "creditcard.trianglebadge.exclamationmark",
                        actionTitle: scopedExpenses.isEmpty ? "Add Expense" : nil,
                        action: scopedExpenses.isEmpty ? { addExpenseAndOpenSheet() } : nil,
                        secondaryTitle: isFiltered ? "Clear Filters" : nil,
                        secondaryAction: isFiltered ? {
                            searchText = ""
                            filter = .all
                        } : nil
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredExpenses) { expense in
                        Button {
                            selectedExpense = expense
                        } label: {
                            expenseRow(expense)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteExpenses)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $selectedExpense) { expense in
            ExpenseFormView(expense: expense, isDraft: false)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingNewExpense, onDismiss: { newExpenseDraft = nil }) {
            NavigationStack {
                if let newExpenseDraft {
                    ExpenseFormView(expense: newExpenseDraft, isDraft: true) {
                        showingNewExpense = false
                    } onCancel: {
                        deleteIfInvalidAndClose(newExpenseDraft)
                    }
                } else {
                    ProgressView("Loading…")
                        .navigationTitle("New Expense")
                }
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Row UI

    private func expenseRow(_ expense: Expense) -> some View {
        let title = expense.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? expense.category.displayName
            : expense.vendor
        let date = expense.date.formatted(date: .abbreviated, time: .omitted)
        let amount = InsightsCurrency.string(cents: expense.amountCents, code: currencyCode)
        let subtitle = [expense.category.displayName, date].joined(separator: " • ")

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Expenses"))
                Image(systemName: expense.category.systemImage)
                    .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
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
    }

    // MARK: - Add / Delete

    private func addExpenseAndOpenSheet() {
        guard let bizID = effectiveBusinessID else {
            SBWLog.ui.problem("❌ No active business selected")
            return
        }

        let expense = Expense(businessID: bizID, date: .now)

        modelContext.insert(expense)
        newExpenseDraft = expense
        showingNewExpense = true

        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save new expense draft: \(error)") }
        Haptics.lightTap()
    }

    private func deleteIfInvalidAndClose(_ expense: Expense) {
        if expense.amountCents <= 0 && expense.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelContext.delete(expense)
        }

        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save after cancel: \(error)") }

        showingNewExpense = false
    }

    private func deleteExpenses(at offsets: IndexSet) {
        let toDelete: [Expense] = offsets.compactMap { idx -> Expense? in
            guard idx < filteredExpenses.count else { return nil }
            return filteredExpenses[idx]
        }

        for expense in toDelete {
            modelContext.delete(expense)
        }

        do { try modelContext.save() }
        catch { SBWLog.ui.problem("Failed to save deletes: \(error)") }
        Haptics.success()
    }
}
