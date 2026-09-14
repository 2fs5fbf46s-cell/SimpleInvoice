import Foundation
import CryptoKit

/// What a signature freezes.
///
/// Signing was already careful — explicit consent, a name, a timestamp, an IP, a
/// stamped PDF. What was missing is that nothing stopped the contract text from
/// changing afterwards. The body was a plain `TextEditor` with no guard, the
/// status picker offered "Draft" on a signed contract, and `/api/portal/index`
/// wrote both unconditionally — so the portal would serve new words under the old
/// signature.
///
/// The backend enforces the same rules in `src/lib/contractSignLock.ts`, and the
/// two must agree on the hash: normalize line endings, trim, SHA-256, hex.
enum ContractSignLock {

    /// Normalize before hashing, so a line-ending difference between the app and
    /// the portal is not read as a content change.
    static func normalize(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SHA-256 of the normalized body, lowercase hex.
    static func bodyHash(_ body: String) -> String {
        let digest = SHA256.hash(data: Data(normalize(body).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the contract text may still be edited.
    static func canEditBody(status: ContractStatus) -> Bool {
        status != .signed
    }

    /// The result of comparing a contract's current text against what was signed.
    enum Integrity: Equatable {
        /// Not signed, so there is nothing to verify.
        case notSigned
        /// Signed before hashes were recorded — nothing to compare against.
        case unverifiable
        case intact
        case changedSinceSigning
    }

    static func verify(
        status: ContractStatus,
        signedBodyHash: String?,
        currentBody: String
    ) -> Integrity {
        guard status == .signed else { return .notSigned }

        let recorded = (signedBodyHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recorded.isEmpty else { return .unverifiable }

        return recorded == bodyHash(currentBody) ? .intact : .changedSinceSigning
    }
}

extension ContractStatus {
    /// The statuses a contract can still be moved between by hand.
    ///
    /// `signed` is deliberately absent: it is set by the act of signing, and it is
    /// terminal. Offering it — and offering a way back out of it — in a picker
    /// meant a signature could be applied or walked back with one tap.
    static var selectableBeforeSigning: [ContractStatus] {
        allCases.filter { $0 != .signed }
    }
}
