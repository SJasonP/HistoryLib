import Foundation
import Observation

@MainActor
@Observable
final class HistorySearchRequests {
    struct Request: Identifiable, Equatable {
        enum Mode { case keywords, naturalLanguage }
        let id = UUID()
        let query: String
        let mode: Mode
    }

    static let shared = HistorySearchRequests()
    private(set) var pending: Request?

    func submit(_ query: String, mode: Request.Mode) throws {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 2_000 else { throw HistorySearchError.invalidCriteria }
        pending = Request(query: query, mode: mode)
    }

    /// Cold-start requests survive until a view is ready; transfers take priority.
    func consume(isBusy: Bool) -> Request? {
        guard !isBusy else { return nil }
        defer { pending = nil }
        return pending
    }
}
