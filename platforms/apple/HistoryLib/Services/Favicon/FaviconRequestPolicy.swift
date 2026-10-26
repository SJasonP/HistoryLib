import Foundation

/// Derive icon requests from the origin, never from a recorded page path/query.
enum FaviconRequestPolicy {
    nonisolated static func origin(for pageURL: URL) -> URL? {
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme
        parts.user = nil
        parts.password = nil
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    nonisolated static func fallbackURLs(for origin: URL) -> [URL] {
        guard let origin = self.origin(for: origin),
              var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return [] }
        return ["/favicon.ico", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"].compactMap { path in
            parts.path = path
            return parts.url
        }
    }

    nonisolated static func permitsIcon(_ url: URL, from origin: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        return url.host?.lowercased() == origin.host?.lowercased()
            && url.scheme?.lowercased() == origin.scheme?.lowercased()
            && (url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))
                == (origin.port ?? (origin.scheme?.lowercased() == "https" ? 443 : 80))
    }
}
