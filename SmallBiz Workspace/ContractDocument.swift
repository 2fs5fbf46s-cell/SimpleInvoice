//
//  ContractDocument.swift
//  SmallBiz Workspace
//

import Foundation

/// A contract body read as the blocks the PDF lays out.
///
/// The markup (see ContractTemplateBodies.swift) is plain text the owner
/// can edit in place. A body without any of it, such as an older contract or
/// the split sheet, is all paragraphs and prints as before.
enum ContractBlock: Equatable {
    case title(String)
    case subtitle(String)
    case heading(String)
    /// "3.2 Deposit. A booking deposit…": number, bold lead-in, the rest.
    case clause(number: String, lead: String?, text: String)
    /// "(a) …" under a clause, or a "• …" line item.
    case item(marker: String, text: String)
    case table(header: [String]?, rows: [[String]])
    case paragraph(String)
    case gap
    case pageBreak
    case signatures
}

enum ContractDocument {
    static let pageBreakMarker = "[[PAGE BREAK]]"
    static let signaturesMarker = "[[SIGNATURES]]"

    /// The current built-in agreements: these get the initials footer and
    /// their signature page where the marker sits.
    static func isStructured(_ body: String) -> Bool {
        body.contains(signaturesMarker)
    }

    static func parse(_ body: String) -> [ContractBlock] {
        var blocks: [ContractBlock] = []
        var tableRows: [[String]] = []
        var tableHeader: [String]?

        func flushTable() {
            guard !tableRows.isEmpty || tableHeader != nil else { return }
            blocks.append(.table(header: tableHeader, rows: tableRows))
            tableRows = []
            tableHeader = nil
        }

        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("|") {
                let cells = tableCells(line)
                if cells.allSatisfy(isSeparatorCell), !cells.isEmpty {
                    // The row above is the header, if it's the table's first.
                    if tableHeader == nil, tableRows.count == 1 {
                        tableHeader = tableRows.removeFirst()
                    }
                } else {
                    tableRows.append(cells)
                }
                continue
            }
            flushTable()

            if line == pageBreakMarker {
                blocks.append(.pageBreak)
            } else if line == signaturesMarker {
                blocks.append(.signatures)
            } else if line.isEmpty {
                blocks.append(.gap)
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.count > 2, line.hasPrefix("_"), line.hasSuffix("_") {
                let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                // An empty subtitle (nothing known yet) prints nothing.
                if !inner.isEmpty { blocks.append(.subtitle(inner)) }
            } else if let clause = clause(line) {
                blocks.append(clause)
            } else if let item = item(line) {
                blocks.append(item)
            } else {
                blocks.append(.paragraph(line))
            }
        }
        flushTable()
        return blocks
    }

    private static func tableCells(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let stripped = cell.replacingOccurrences(of: ":", with: "")
        return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
    }

    /// "12.3 Governing Law and Disputes. This Agreement…"
    private static func clause(_ line: String) -> ContractBlock? {
        guard let space = line.firstIndex(of: " ") else { return nil }
        let number = String(line[..<space])
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }

        let rest = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
        // A short, capitalized phrase ending in a period is the lead-in.
        if let stop = rest.range(of: ". "), rest.first?.isUppercase == true {
            let lead = String(rest[..<stop.upperBound]).trimmingCharacters(in: .whitespaces)
            if lead.split(separator: " ").count <= 9 {
                return .clause(number: number, lead: lead, text: String(rest[stop.upperBound...]))
            }
        } else if rest.hasSuffix("."), rest.split(separator: " ").count <= 9, rest.first?.isUppercase == true,
                  !rest.dropLast().contains(".") {
            return .clause(number: number, lead: rest, text: "")
        }
        return .clause(number: number, lead: nil, text: rest)
    }

    private static func item(_ line: String) -> ContractBlock? {
        if line.hasPrefix("• ") {
            return .item(marker: "•", text: String(line.dropFirst(2)))
        }
        guard line.hasPrefix("("), let close = line.firstIndex(of: ")") else { return nil }
        let marker = line[line.index(after: line.startIndex)..<close]
        guard (1...3).contains(marker.count), marker.allSatisfy({ $0.isLetter && $0.isLowercase }) else { return nil }
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return .item(marker: "(\(marker))", text: text)
    }
}
