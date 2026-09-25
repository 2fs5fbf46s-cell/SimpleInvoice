import XCTest

/// Every server path the app calls has a route on the server.
///
/// The notification inbox called /api/notifications, which never existed
/// (the route is /api/notifications/list), so the inbox was always empty and
/// nothing said why. This reads the app's sources and, when the backend repo
/// sits next to this one as it does on the build machine, checks each path.
final class APIRouteContractTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appAPIPaths() throws -> Set<String> {
        let sources = repoRoot.appendingPathComponent("SmallBiz Workspace")
        let regex = try NSRegularExpression(pattern: #""(/api/[A-Za-z0-9/_\-]+)""#)
        var paths = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift", let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) { paths.insert(String(text[r])) }
            }
        }
        return paths
    }

    func testEveryPathTheAppCallsExistsOnTheServer() throws {
        let apiRoot = repoRoot.deletingLastPathComponent()
            .appendingPathComponent("smallbizworkspace-portal-backend/src/app")
        guard FileManager.default.fileExists(atPath: apiRoot.path) else {
            throw XCTSkip("Backend repo not beside this one.")
        }

        let paths = try appAPIPaths()
        XCTAssertGreaterThan(paths.count, 30, "expected to find the app's API paths")

        let missing = paths.filter { path in
            let route = apiRoot.appendingPathComponent(path).appendingPathComponent("route.ts")
            return !FileManager.default.fileExists(atPath: route.path)
        }
        XCTAssertEqual(missing.sorted(), [], "The app calls paths the server doesn't have")
    }
}
