import Foundation

/// Validated values, never executable predicates or model-generated queries.
struct HistorySearchFilter: Equatable, Sendable {
    var keywords: [String] = []
    var domain: String = ""
    var browser: String = ""
    var startDate: Date?
    var endDate: Date? // Exclusive; local calendar day boundaries are resolved before querying.

    var isActive: Bool {
        !keywords.isEmpty || !domain.isEmpty || !browser.isEmpty || startDate != nil || endDate != nil
    }

    func validated() throws -> Self {
        var result = self
        result.keywords = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard result.keywords.count <= 16, result.keywords.allSatisfy({ $0.count <= 2_000 }),
              result.keywords.reduce(0, { $0 + $1.count }) <= 4_000 else {
            throw HistorySearchError.invalidCriteria
        }
        result.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !result.domain.isEmpty {
            guard result.domain.count <= 253,
                  !result.domain.contains(where: { "/:@?#\\".contains($0) || $0.isWhitespace }),
                  let host = URL(string: "https://" + result.domain)?.host,
                  !host.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.isEmpty }) else {
                throw HistorySearchError.invalidDomain
            }
            result.domain = host.lowercased()
        }
        result.browser = browser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.browser.isEmpty {
            guard let canonical = ["Safari", "Chrome"].first(where: {
                $0.caseInsensitiveCompare(result.browser) == .orderedSame
            }) else { throw HistorySearchError.invalidCriteria }
            result.browser = canonical
        }
        if let startDate, let endDate, startDate >= endDate {
            throw HistorySearchError.invalidDateRange
        }
        return result
    }

    func matches(url: String, title: String, browser: String, visitedAt: Date) -> Bool {
        if let startDate, visitedAt < startDate { return false }
        if let endDate, visitedAt >= endDate { return false }
        if !self.browser.isEmpty, self.browser.caseInsensitiveCompare(browser) != .orderedSame { return false }
        if !domain.isEmpty {
            guard let host = URL(string: url)?.host?.lowercased(),
                  host == domain || host.hasSuffix("." + domain) else { return false }
        }
        return keywords.allSatisfy { term in
            url.localizedCaseInsensitiveContains(term) || title.localizedCaseInsensitiveContains(term)
        }
    }

    static func calendarDate(_ value: String?, timeZone: TimeZone) throws -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value),
              formatter.string(from: date) == value else { throw HistorySearchError.invalidDateRange }
        return date
    }
}

enum HistorySearchError: LocalizedError {
    case invalidCriteria, invalidDomain, invalidDateRange, unavailable, interpretationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCriteria: String(localized: "Check the search terms and browser, then try again.")
        case .invalidDomain: String(localized: "Enter a domain such as example.com, without a path or scheme.")
        case .invalidDateRange: String(localized: "The end of the date range must be after its start.")
        case .unavailable: String(localized: "On-device interpretation is unavailable. You can edit the filters manually.")
        case .interpretationFailed: String(localized: "The request could not be interpreted. Edit the filters or try a simpler request.")
        }
    }
}
