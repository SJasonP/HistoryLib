import Foundation
import ImageIO

actor FaviconStore {
    static let shared = FaviconStore()

    private var memoryCache: [String: Data] = [:]
    private var memoryCacheOrder: [String] = []
    private var missingHostRetryAt: [String: Date] = [:]
    private var inFlightByHost: [String: Task<Data?, Never>] = [:]
    private var activeFetches = 0
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []

    private let cacheDirectory: URL
    private let session: URLSession
    private let maxMemoryCacheEntries = 800
    private let missingHostRetryInterval: TimeInterval = 6 * 60 * 60
    private let maxConcurrentFetches = 6

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("HistoryLibFavicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func faviconData(for pageURLString: String) async -> Data? {
        guard let pageURL = URL(string: pageURLString),
              let host = pageURL.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if let cached = memoryCache[host] {
            return cached
        }

        if let retryAt = missingHostRetryAt[host], retryAt > Date() {
            return nil
        }
        missingHostRetryAt.removeValue(forKey: host)

        let diskURL = cacheFileURL(for: host)
        if let diskData = try? Data(contentsOf: diskURL), isValidImageData(diskData) {
            cacheInMemory(host: host, data: diskData)
            return diskData
        }

        if let inFlight = inFlightByHost[host] {
            return await inFlight.value
        }

        let task = Task<Data?, Never> { [self] in
            await acquireFetchSlot()
            defer { releaseFetchSlot() }

            if let fetched = await fetchFaviconData(for: pageURL) {
                cacheInMemory(host: host, data: fetched)
                try? fetched.write(to: diskURL, options: .atomic)
                return fetched
            }

            missingHostRetryAt[host] = Date().addingTimeInterval(missingHostRetryInterval)
            return nil
        }

        inFlightByHost[host] = task
        let result = await task.value
        inFlightByHost.removeValue(forKey: host)
        return result
    }

    func clearAllCache() {
        memoryCache.removeAll(keepingCapacity: false)
        memoryCacheOrder.removeAll(keepingCapacity: false)
        missingHostRetryAt.removeAll(keepingCapacity: false)
        inFlightByHost.removeAll(keepingCapacity: false)

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func fetchFaviconData(for pageURL: URL) async -> Data? {
        let candidates = await faviconCandidates(for: pageURL)
        for url in candidates {
            if let data = await fetchData(url: url), isValidImageData(data) {
                return data
            }
        }
        return nil
    }

    private func faviconCandidates(for pageURL: URL) async -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        let htmlSources = [pageURL, rootURL(of: pageURL)].compactMap { $0 }
        for sourceURL in htmlSources {
            if let html = await fetchHTML(url: sourceURL) {
                for iconURL in parseIconURLs(fromHTML: html, pageURL: sourceURL) {
                    if seen.insert(iconURL.absoluteString).inserted {
                        urls.append(iconURL)
                    }
                }
            }
        }

        if let host = pageURL.host {
            let preferredScheme = (pageURL.scheme?.lowercased() == "http" || pageURL.scheme?.lowercased() == "https")
                ? pageURL.scheme!.lowercased()
                : nil
            let fallbackSchemes = [preferredScheme, "https", "http"].compactMap { $0 }

            for scheme in fallbackSchemes {
                for path in ["/favicon.ico", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"] {
                    var components = URLComponents()
                    components.scheme = scheme
                    components.host = host
                    components.path = path
                    if let fallback = components.url,
                       seen.insert(fallback.absoluteString).inserted {
                        urls.append(fallback)
                    }
                }
            }
        }

        return urls
    }

    private func fetchHTML(url: URL) async -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 8

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }

        if let html = String(data: data, encoding: .utf8) {
            return String(html.prefix(300_000))
        }
        if let html = String(data: data, encoding: .isoLatin1) {
            return String(html.prefix(300_000))
        }
        return nil
    }

    private func fetchData(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 8

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }

        return data
    }

    private func parseIconURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        guard let linkRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }

        let source = html as NSString
        let range = NSRange(location: 0, length: source.length)
        let matches = linkRegex.matches(in: html, options: [], range: range)

        var urls: [URL] = []
        for match in matches {
            let tag = source.substring(with: match.range)

            let relValue = attributeValue(named: "rel", in: tag)?.lowercased() ?? ""
            guard relValue.contains("icon") else {
                continue
            }

            guard let href = attributeValue(named: "href", in: tag)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !href.isEmpty,
                !href.lowercased().hasPrefix("data:"),
                let resolved = URL(string: href, relativeTo: pageURL)?.absoluteURL,
                let scheme = resolved.scheme?.lowercased(),
                scheme == "http" || scheme == "https" else {
                continue
            }

            urls.append(resolved)
        }

        return urls
    }

    private func attributeValue(named name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let source = tag as NSString
        let range = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return source.substring(with: match.range(at: group))
        }
        return nil
    }

    private func cacheFileURL(for host: String) -> URL {
        let sanitized = host.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent("\(sanitized).bin")
    }

    private func cacheInMemory(host: String, data: Data) {
        memoryCache[host] = data
        memoryCacheOrder.removeAll { $0 == host }
        memoryCacheOrder.append(host)

        while memoryCacheOrder.count > maxMemoryCacheEntries {
            let oldestHost = memoryCacheOrder.removeFirst()
            memoryCache.removeValue(forKey: oldestHost)
        }
    }

    private func acquireFetchSlot() async {
        if activeFetches < maxConcurrentFetches {
            activeFetches += 1
            return
        }

        await withCheckedContinuation { continuation in
            fetchWaiters.append(continuation)
        }
    }

    private func releaseFetchSlot() {
        if let next = fetchWaiters.first {
            fetchWaiters.removeFirst()
            next.resume()
        } else {
            activeFetches = max(0, activeFetches - 1)
        }
    }

    private func rootURL(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func isValidImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }
}
