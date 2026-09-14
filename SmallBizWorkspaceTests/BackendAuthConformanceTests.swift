import XCTest
@testable import SmallBizWorkspace

/// Guards on how requests to the portal backend are authenticated.
///
/// These exist because of a real bug, not a hypothetical one. Moving the app onto
/// per-business device tokens converted every request builder that set
/// `x-portal-admin` — and missed all eleven that set `x-admin-key` instead,
/// because the bulk edit matched on the header string. Those eleven kept sending
/// only the shared key, and every business-scoped route they call answers 401.
/// The whole booking admin surface was unreachable: the slug, the request list,
/// settings, deposits, analytics, totals.
///
/// The same edit also rewrote the line *inside* the new helper, turning its first
/// statement into a call to itself. Nothing catches unbounded recursion at
/// compile time, so it shipped as a crash on the first authenticated call.
///
/// Both are invisible to a build and to every other test in this target, which is
/// what these assertions are for.
final class BackendAuthConformanceTests: XCTestCase {

    private func portalBackendSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let source = testFile
            .deletingLastPathComponent()   // SmallBizWorkspaceTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("SmallBiz Workspace", isDirectory: true)
            .appendingPathComponent("PortalBackend.swift")

        guard let text = try? String(contentsOf: source, encoding: .utf8) else {
            throw XCTSkip("Could not read PortalBackend.swift at \(source.path)")
        }
        return text
    }

    /// Every auth header goes through `applyAuthHeaders`, so there is one place
    /// that can be got right and one place that can be got wrong.
    func testAuthHeadersAreSetInExactlyOnePlace() throws {
        let source = try portalBackendSource()
        let headers = ["x-portal-admin", "x-portal-admin-key", "x-admin-key", "x-sbw-business-token"]

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Locate the helper rather than hardcoding line numbers, so this keeps
        // working when the file moves around.
        guard let helperStart = lines.firstIndex(where: {
            $0.contains("fileprivate func applyAuthHeaders")
        }) else {
            return XCTFail("applyAuthHeaders is gone; this guard needs updating")
        }

        // Its body ends at the first line that closes it at the same indentation.
        let helperEnd = lines[(helperStart + 1)...].firstIndex(where: { $0 == "    }" })
            ?? (helperStart + 8)

        var offenders: [String] = []

        for (index, text) in lines.enumerated() {
            guard text.contains("forHTTPHeaderField") else { continue }
            guard headers.contains(where: { text.contains("\"\($0)\"") }) else { continue }
            guard !(helperStart...helperEnd).contains(index) else { continue }

            offenders.append("line \(index + 1): \(text.trimmingCharacters(in: .whitespaces))")
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            These set an auth header directly instead of calling applyAuthHeaders, \
            so they will not send the business token and the route will answer 401:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The recursion bug, stated as a rule: the helper must not call itself.
    func testTheAuthHelperDoesNotCallItself() throws {
        let source = try portalBackendSource()

        guard let start = source.range(of: "fileprivate func applyAuthHeaders") else {
            return XCTFail("applyAuthHeaders is gone; this guard needs updating")
        }

        // The helper is short — take the next few lines, which is its whole body.
        let body = source[start.lowerBound...].prefix(400)
        let afterSignature = body.dropFirst("fileprivate func applyAuthHeaders".count)

        XCTAssertFalse(
            afterSignature.contains("applyAuthHeaders(&req"),
            "applyAuthHeaders calls itself — that is unbounded recursion and it crashes on the first authenticated request"
        )
    }

    /// Both credentials have to actually be attached: the business token is what
    /// authorizes scoped routes, the shared key is still accepted by the few
    /// platform-level ones.
    func testTheAuthHelperSendsBothCredentials() throws {
        let source = try portalBackendSource()

        XCTAssertTrue(
            source.contains(#"req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")"#),
            "the shared key is still needed to bootstrap registration and for platform routes"
        )
        XCTAssertTrue(
            source.contains(#"req.setValue(token, forHTTPHeaderField: "x-sbw-business-token")"#),
            "the business token is what authorizes every business-scoped route"
        )
    }

    /// Sanity: the helper is actually used, and widely. If this drops to a handful
    /// someone has started hand-rolling headers again.
    func testTheAuthHelperIsUsedByEveryRequestBuilder() throws {
        let source = try portalBackendSource()
        let uses = source.components(separatedBy: "applyAuthHeaders(&req").count - 1

        XCTAssertGreaterThanOrEqual(
            uses, 20,
            "only \(uses) request builders attach auth; the rest will answer 401"
        )
    }
}
