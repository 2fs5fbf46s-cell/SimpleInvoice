import Foundation
import SwiftData

/// Who the invoice was billed to, copied onto the invoice itself.
///
/// Invoices already snapshot the *business* side, so editing your own profile
/// doesn't rewrite history. Nothing did that for the client, and `Invoice.client`
/// carries no delete rule — so deleting a client left every invoice ever sent to
/// them surviving with `client == nil`, rendering with a blank bill-to block.
/// Paid ones included.
///
/// This is the other half of that symmetry. The rules live in
/// `ClientSnapshotPolicy` rather than in the model or the view, so the part worth
/// getting right is testable without a `ModelContainer`.
struct ClientSnapshot: Codable, Equatable, Sendable {
    var name: String
    var email: String
    var phone: String
    var address: String

    init(name: String = "", email: String = "", phone: String = "", address: String = "") {
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
    }

    /// True when there is nothing here worth showing on a document.
    var isEmpty: Bool {
        [name, email, phone, address].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// When to refresh the stored copy, and which copy a document should show.
///
/// Deliberately mirrors the business snapshot's lock behavior: a draft tracks the
/// live record so corrections flow through, and a finalized document stops
/// tracking so it keeps saying what it said when it was sent.
enum ClientSnapshotPolicy {

    /// The copy to write back to the invoice, or `nil` to leave what is stored
    /// alone.
    ///
    /// - A locked invoice never overwrites a snapshot it already has — that is
    ///   the whole point of locking. It will still backfill one if it has none,
    ///   because an invoice finalized before this existed is better off with a
    ///   late snapshot than with nothing.
    /// - An unlocked draft tracks the live client.
    /// - A live client that has been emptied out, or deleted, never overwrites a
    ///   good stored copy with a blank one.
    static func snapshotToStore(
        live: ClientSnapshot?,
        stored: ClientSnapshot?,
        isLocked: Bool
    ) -> ClientSnapshot? {
        guard let live, !live.isEmpty else { return nil }
        if isLocked && stored != nil { return nil }
        if live == stored { return nil }
        return live
    }

    /// The party a rendered document should show.
    ///
    /// A locked invoice prefers what it recorded; everything else prefers the
    /// live record and falls back to the snapshot, which is the case that matters
    /// — the client row is gone and this is all that is left of them.
    static func partyToRender(
        live: ClientSnapshot?,
        stored: ClientSnapshot?,
        isLocked: Bool
    ) -> ClientSnapshot? {
        if isLocked, let stored, !stored.isEmpty { return stored }
        if let live, !live.isEmpty { return live }
        if let stored, !stored.isEmpty { return stored }
        return live ?? stored
    }
}

/// What deleting a client would take with it.
///
/// Swipe-to-delete used to destroy the record with no confirmation and no hint
/// that anything else referenced it. Counting first lets the confirmation say
/// what is actually at stake.
struct ClientDeletionImpact: Equatable {
    var invoices: Int = 0
    var estimates: Int = 0
    var jobs: Int = 0
    var contracts: Int = 0

    var total: Int { invoices + estimates + jobs + contracts }
    var hasHistory: Bool { total > 0 }

    /// One line naming everything that references this client, largest first.
    ///
    /// Empty when nothing does, so the caller can skip the warning entirely.
    var summary: String {
        let parts: [(Int, String, String)] = [
            (invoices, "invoice", "invoices"),
            (estimates, "estimate", "estimates"),
            (jobs, "job", "jobs"),
            (contracts, "contract", "contracts"),
        ]

        let phrases = parts
            .filter { $0.0 > 0 }
            .sorted { $0.0 > $1.0 }
            .map { count, singular, plural in "\(count) \(count == 1 ? singular : plural)" }

        switch phrases.count {
        case 0: return ""
        case 1: return phrases[0]
        case 2: return "\(phrases[0]) and \(phrases[1])"
        default:
            return phrases.dropLast().joined(separator: ", ") + ", and " + phrases[phrases.count - 1]
        }
    }

    /// The body of the confirmation dialog.
    func confirmationMessage(clientName: String) -> String {
        let who = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = who.isEmpty ? "this client" : who

        guard hasHistory else {
            return "\(name) has no invoices, jobs or contracts. This can't be undone."
        }

        return """
        \(name) is referenced by \(summary).

        Those records stay, and keep the name and address they were sent with. \
        You just won't be able to open \(name) from them any more. This can't be undone.
        """
    }
}

extension ClientDeletionImpact {
    /// Count what points at this client.
    ///
    /// Invoices, estimates and contracts come off the client's own
    /// relationships. Jobs link by `clientID` with no relationship at all, so
    /// they have to be counted from the caller's list.
    @MainActor
    static func forClient(_ client: Client, jobs: [Job]) -> ClientDeletionImpact {
        let documents = client.invoices ?? []

        return ClientDeletionImpact(
            invoices: documents.filter { $0.documentType != "estimate" }.count,
            estimates: documents.filter { $0.documentType == "estimate" }.count,
            jobs: jobs.filter { $0.clientID == client.id }.count,
            contracts: (client.contracts ?? []).count
        )
    }
}
