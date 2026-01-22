import Foundation
import CryptoKit

enum PortalCrypto {
    static func randomToken() -> String {
        // URL-safe token
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Short invite code intended for manual copy/paste during the no-backend phase.
    /// Not stored directly—only its SHA256 hash is persisted.
    static func randomInviteCode() -> String {
        // 12-char base32-ish (no confusing characters)
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var out: [Character] = []
        out.reserveCapacity(12)
        for _ in 0..<12 {
            out.append(alphabet.randomElement()!)
        }
        return String(out)
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
