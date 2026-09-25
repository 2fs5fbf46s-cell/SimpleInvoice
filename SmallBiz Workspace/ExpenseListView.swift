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
    /// Any day in the month being shown.
    @State private var month: Date = .now

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
        // The month being shown; a search looks across every month.
        guard !query.isEmpty else { return byFilter.filter { monthInterval.contains($0.date) } }

        return byFilter.filter { expense in
            if expense.vendor.localizedCaseInsensitiveContains(query) { return true }
            if expense.notes.localizedCaseInsensitiveContains(query) { return true }
            if expense.category.displayName.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    private var monthInterval: DateInterval { MoneyMath.thisMonth(month) }

    private var yearInterval: DateInterval {
        Calendar.current.dateInterval(of: .year, for: month) ?? monthInterval
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private func money(_ cents: Int) -> String { InsightsCurrency.string(cents: cents, code: currencyCode) }

    private var monthHeader: some View {
        let spent = MoneyMath.spent(scopedExpenses, in: monthInterval)
        let deductible = MoneyMath.deductible(scopedExpenses, in: monthInterval)
        let yearSpent = MoneyMath.spent(scopedExpenses, in: yearInterval)
        let monthName = month.formatted(.dateTime.month(.wide))
        return VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            HStack(spacing: 8) {
                summaryTile("Spent in \(monthName)", money(spent.cents), "\(spent.count) expense\(spent.count == 1 ? "" : "s")")
                summaryTile("Tax deductible", money(deductible), "this month")
            }
            Text("\(month.formatted(.dateTime.year())) so far: \(money(yearSpent.cents)) spent, \(money(MoneyMath.deductible(scopedExpenses, in: yearInterval))) deductible")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryTile(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.headline).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var categoryBreakdown: [(ExpenseCategory, Int)] {
        let inMonth = scopedExpenses.filter { monthInterval.contains($0.date) }
        return Dictionary(grouping: inMonth, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.amountCents }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private func shiftMonth(_ by: Int) {
        month = Calendar.current.date(byAdding: .month, value: by, to: month) ?? month
    }

    private var yearCSV: URL? {
        ExpenseExport.csvFile(
            expenses: scopedExpenses.filter { yearInterval.contains($0.date) },
            year: Calendar.current.component(.year, from: month)
        )
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
                                .background(Circle().fill(SBWTheme.brand.opacity(0.2)))
                        }
                    }
                }

                if !isSearching {
                    Section { monthHeader }
                }

                Section {
                    SBWFilterChips(
                        options: Filter.options,
                        title: { $0.title },
                        selection: $filter
                    )
                }

                if !isSearching {
                    if filter == .all, categoryBreakdown.count > 1 {
                        Section("By category") {
                            ForEach(categoryBreakdown, id: \.0) { category, cents in
                                Button { filter = .category(category) } label: {
                                    LabeledContent(category.displayName, value: money(cents))
                                        .monospacedDigit()
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
                        title: scopedExpenses.isEmpty ? "No Expenses Yet" : (isSearching || filter != .all ? "No Results" : "Nothing spent this month"),
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
                Menu {
                    if let url = yearCSV {
                        ShareLink(item: url) {
                            Label("Export \(month.formatted(.dateTime.year())) as Spreadsheet", systemImage: "tablecells")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
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

/// The year's expenses as a spreadsheet (CSV) for an accountant.
enum ExpenseExport {
    static func csv(_ expenses: [Expense]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        func field(_ value: String) -> String {
            let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return needsQuotes ? "\"\(escaped)\"" : escaped
        }
        var lines = ["Date,Vendor,Category,Amount,Tax deductible,Notes"]
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            let amount = String(format: "%.2f", Double(e.amountCents) / 100)
            lines.append([df.string(from: e.date), field(e.vendor), field(e.category.displayName), amount,
                          e.isTaxDeductible ? "Yes" : "No", field(e.notes)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func csvFile(expenses: [Expense], year: Int) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Expenses \(year).csv")
        do {
            try csv(expenses).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
