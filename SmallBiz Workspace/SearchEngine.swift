import Foundation

/// One record as search sees it: what it's called, the line under that, and
/// every word it can be found by.
///
/// Built from the SwiftData models by `SearchDocuments`, and used by both the
/// in-app search and iPhone Spotlight, so the two always find the same things.
struct SearchDocument: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case client, invoice, estimate, job, contract, expense

        var sectionTitle: String {
            switch self {
            case .client: return "Clients"
            case .invoice: return "Invoices"
            case .estimate: return "Estimates"
            case .job: return "Jobs"
            case .contract: return "Contracts"
            case .expense: return "Expenses"
            }
        }

        var systemImage: String {
            switch self {
            case .client: return "person.crop.circle"
            case .invoice: return "doc.plaintext"
            case .estimate: return "doc.text.magnifyingglass"
            case .job: return "hammer"
            case .contract: return "signature"
            case .expense: return "creditcard"
            }
        }
    }

    let kind: Kind
    let recordID: UUID
    let title: String
    let subtitle: String
    /// Newest first among equally good matches.
    let date: Date
    /// Folded (lowercase, no accents) text every word of a query must appear in.
    let haystack: String

    /// "invoice:<uuid>". Also the Spotlight identifier, so a Spotlight tap
    /// names the record it came from.
    var id: String { "\(kind.rawValue):\(recordID.uuidString)" }

    init(kind: Kind, recordID: UUID, title: String, subtitle: String, date: Date, terms: [String]) {
        self.kind = kind
        self.recordID = recordID
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.haystack = SearchEngine.fold(([title] + terms).joined(separator: " "))
    }

    /// The kind and record an `id` names, or nil for anything else.
    static func parse(_ identifier: String) -> (kind: Kind, recordID: UUID)? {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        return (kind, id)
    }
}

enum SearchEngine {
    struct Section: Equatable {
        let kind: SearchDocument.Kind
        let documents: [SearchDocument]
        /// How many matched, when more than `documents` shows.
        let totalCount: Int
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    /// Matching records grouped by kind, in `Kind` order. A record matches
    /// when every word of the query appears somewhere in it, so "smith
    /// kitchen" finds the Smith kitchen job and not every Smith.
    static func sections(for query: String, in documents: [SearchDocument], limitPerKind: Int = 25) -> [Section] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let folded = fold(query).trimmingCharacters(in: .whitespaces)

        let matches = documents
            .filter { document in words.allSatisfy { document.haystack.contains($0) } }
            .map { (document: $0, rank: rank($0, query: folded, firstWord: words[0])) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.document.date > $1.document.date }
            .map(\.document)

        return SearchDocument.Kind.allCases.compactMap { kind in
            let ofKind = matches.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            return Section(kind: kind, documents: Array(ofKind.prefix(limitPerKind)), totalCount: ofKind.count)
        }
    }

    /// Lower is better: the title starts with the query, then a word of the
    /// title starts with it, then the title contains it, then anything else.
    private static func rank(_ document: SearchDocument, query: String, firstWord: String) -> Int {
        let title = fold(document.title)
        if title.hasPrefix(query) { return 0 }
        if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(firstWord) }) { return 1 }
        if title.contains(query) { return 2 }
        return 3
    }

    /// The ways someone types an amount: "2000", "2000.50", "2,000.50",
    /// "$2,000.50".
    static func amountTerms(cents: Int) -> [String] {
        let dollars = cents / 100
        let remainder = abs(cents % 100)
        let plain = remainder == 0 ? "\(dollars)" : "\(dollars).\(String(format: "%02d", remainder))"
        let grouped = (dollars.formatted(.number.grouping(.automatic))) + String(format: ".%02d", remainder)
        return [plain, "\(dollars).\(String(format: "%02d", remainder))", grouped, "$" + grouped]
    }

    /// A phone number's digits alone, so "5551234" finds "(555) 123-4".
    static func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }
}
