import AppIntents

struct SearchHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Search History"
    static var description = IntentDescription("Find matching browser history in HistoryLib.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Search keywords") var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        try HistorySearchRequests.shared.submit(query, mode: .keywords)
        return .result()
    }
}

struct PrepareNaturalHistorySearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Prepare Natural Language Search"
    static var description = IntentDescription("Open HistoryLib to interpret a request and review its search filters.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Describe your search") var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        try HistorySearchRequests.shared.submit(query, mode: .naturalLanguage)
        return .result()
    }
}

@available(iOS 27.0, macOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchHistoryWithSiriIntent: ShowInAppSearchResultsIntent {
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        try HistorySearchRequests.shared.submit(criteria.term, mode: .keywords)
        return .result()
    }
}

struct HistorySearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchHistoryIntent(),
            phrases: ["Search history in \(.applicationName)"],
            shortTitle: "Search History", systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: PrepareNaturalHistorySearchIntent(),
            phrases: ["Find a page with \(.applicationName)"],
            shortTitle: "Natural Language Search", systemImageName: "sparkles"
        )
    }
}
