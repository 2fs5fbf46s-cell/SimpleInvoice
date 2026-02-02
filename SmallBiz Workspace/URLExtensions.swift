import Foundation

extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: queryItems)
        components.queryItems = items
        return components.url ?? self
    }
}
