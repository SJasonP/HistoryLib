import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreData

#if !os(macOS)
import UIKit
#endif

enum HistoryDefaultExpandLevel: String, CaseIterable, Identifiable {
    case none
    case year
    case month
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return String(localized: "Do Not Expand")
        case .year:
            return String(localized: "Year")
        case .month:
            return String(localized: "Month")
        case .day:
            return String(localized: "Day")
        }
    }
}

enum HistoryRecordTapAction: String, CaseIterable, Identifiable {
    case none
    case copyURL
    case openBrowser

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .none:
            "Do Nothing"
        case .copyURL:
            "Copy Full URL"
        case .openBrowser:
            "Open in Browser"
        }
    }
}

enum HistoryRecordTapActionMigration {
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: "record_tap_action") == nil,
              let legacyValue = defaults.object(forKey: "open_record_in_browser_on_click") as? Bool else {
            return
        }
        defaults.set(
            legacyValue ? HistoryRecordTapAction.openBrowser.rawValue : HistoryRecordTapAction.none.rawValue,
            forKey: "record_tap_action"
        )
    }
}

struct ContentView: View {
    enum AppTab: String, Hashable {
        case summary
        case library
        case manage
    }

    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase

    @AppStorage("show_history_time") var showHistoryTime = true
    @AppStorage("show_site_icons") var showSiteIcons = true
    @AppStorage("enable_delete") var enableDelete = false
    @AppStorage("record_tap_action") var recordTapActionRaw = HistoryRecordTapAction.openBrowser.rawValue
    @AppStorage("default_expand_level") var defaultExpandLevelRaw = HistoryDefaultExpandLevel.day.rawValue
    @AppStorage("advanced_search_enabled") var advancedSearchEnabled = false
    @AppStorage("show_direct_search_results_on_iphone") var showDirectSearchResultsOnIPhone = true
    @AppStorage("last_selected_tab") var lastSelectedTabRaw = AppTab.summary.rawValue
    @AppStorage("persistence_backend") var persistenceBackend = "unknown"
    @AppStorage("persistence_error") var persistenceError = ""

#if os(macOS)
    @Environment(\.openSettings) var openSettings
#endif

    @State var isFileImporterPresented = false
    @State var isFileExporterPresented = false
    @State var searchText = ""
    @State var selectedTab: AppTab = .summary
    @State var libraryNavigationPath: [HistoryYearDestination] = []
    @State var expandedYears: Set<Int> = []
    @State var expandedMonths: Set<Date> = []
    @State var expandedDays: Set<Date> = []
    @State var importFeedbackMessage = ""
    @State var showingImportFeedback = false
    @State var deleteFeedbackMessage = ""
    @State var showingDeleteFeedback = false
    @State var exportFeedbackMessage = ""
    @State var showingExportFeedback = false
    @State var exportDocument: ExportFileDocument?
    @State var exportContentType: UTType = .data
    @State var exportFilename = "history-export"
    @State var exportCleanupDirectoryURL: URL?
    @State var isPreparingExport = false
    @State var exportProgressFraction = 0.0
    @State var exportProgressMessage = String(localized: "Preparing export...")
    @State var isCancellingExport = false
    @State var exportPreparationTask: Task<Void, Never>?

    @State var isImporting = false
    @State var importProgressFraction: Double?
    @State var importProgressMessage = String(localized: "Preparing import...")
    @State var importProgressImportedRecordCount = 0
    @State var importProgressSkippedRecordCount = 0
    @State var isCancellingImport = false
    @State var importTask: Task<Void, Never>?
    @State var pendingEncryptedImportURL: URL?
    @State var showingImportPasswordPrompt = false
    @State var importArchivePassword = ""
    @State var importPasswordErrorMessage = ""

    @State var searchFilter = HistorySearchFilter()
    @State var searchGeneration = 0
    @State var showingSearchFilters = false
    @State var naturalSearchRequest = ""
    @State var searchRequests = HistorySearchRequests.shared
    @State var showingSearchError = false
    @State var searchErrorMessage = ""
    @State var searchResults: [Item] = []
    @State var hasMoreSearchResults = false
    @State var isLoadingSearchResults = false
    @State var searchScanOffset = 0
    @State var searchReloadTask: Task<Void, Never>?
    @State var searchLoadTask: Task<Void, Never>?

    @State var directoryDayStarts: [Date] = []
    @State var isDirectoryLoading = false
    @State var directoryBuildTask: Task<Void, Never>?
    @State var directoryBuildGeneration = 0
    // True once `dayItemCounts` holds every day's count (from a completed scan or
    // a loaded cache), so the persisted count cache can be updated in place.
    @State var directoryCountsAreComplete = false

    @State var dayItemCounts: [Date: Int] = [:]
    @State var loadingDayCounts: Set<Date> = []
    @State var dayLoadedItems: [Date: [Item]] = [:]
    @State var dayItemOffsets: [Date: Int] = [:]
    @State var dayHasMoreItems: [Date: Bool] = [:]
    @State var loadingDayItems: Set<Date> = []
    @State var dayItemLoadGenerations: [Date: Int] = [:]

    @State var totalRecordCount = 0
    @State var oldestRecordDate: Date?
    @State var newestRecordDate: Date?
    @State var latestSummarySnapshot: SummarySnapshot?
    @State var summaryGenerationToken = 0
    @State var summaryGenerationTask: Task<Void, Never>?
    @State var showingStorageModeAlert = false
    @State var showingCopyFeedback = false
    @State var copyFeedbackTask: Task<Void, Never>?
    @State var isBackgroundDedupRunning = false
    @State var backgroundDedupTask: Task<Void, Never>?
    @State var lastBackgroundDedupRunAt: Date = .distantPast
    @State var derivedRefreshTask: Task<Void, Never>?

    let importer = HistoryImporter()
    let exporter = HistoryExporter()
    let calendar = Calendar.current
    let searchPageSize = 300
    let searchScanChunkSize = 1_000
    let directoryScanChunkSize = 2_000
    let dayItemsPageSize = 200

    var body: some View {
        mainTabView
            .allowsHitTesting(!isPreparingExport && !isImporting)
            .overlay {
                if isPreparingExport {
                    exportProgressOverlay
                } else if isImporting {
                    importProgressOverlay
                }
            }
            .overlay(alignment: .bottom) {
                if showingCopyFeedback {
                    Text("Copied")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .floatingFeedbackSurface()
                        .padding(.bottom, isIPhone ? 96 : 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.json, .folder, .zip, .historyLibArchive]
            ) { result in
                handleImporterResult(result)
            }
            .fileExporter(
                isPresented: $isFileExporterPresented,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                handleFileExporterCompletion(result)
            }
            .sheet(isPresented: $showingImportPasswordPrompt) {
                ArchivePasswordPrompt(
                    password: $importArchivePassword,
                    errorMessage: importPasswordErrorMessage,
                    onCancel: cancelPasswordProtectedImport,
                    onSubmit: submitPasswordProtectedImport
                )
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingSearchFilters, onDismiss: consumeSearchRequest) {
                HistorySearchSheet(
                    initialFilter: effectiveSearchFilter, initialRequest: naturalSearchRequest,
                    onApply: applySearchFilter
                )
            }
            .alert("Search Error", isPresented: $showingSearchError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(searchErrorMessage)
            }
            .alert("Import Result", isPresented: $showingImportFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importFeedbackMessage)
            }
            .alert("Delete Result", isPresented: $showingDeleteFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteFeedbackMessage)
            }
            .alert("Export Result", isPresented: $showingExportFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportFeedbackMessage)
            }
            .alert(storageModeAlertTitle, isPresented: $showingStorageModeAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(storageModeMessage)
            }
            .safeAreaInset(edge: .top) {
                if !canMutateHistoryData {
                    storageModeBanner
                }
            }
            .onAppear {
                selectedTab = restoredTab(from: lastSelectedTabRaw)
                applyDefaultExpansion(reset: true)
                refreshSummaryStats()
                loadLatestSummarySnapshot()
                if totalRecordCount > 0,
                   latestSummarySnapshot == nil || latestSummarySnapshot?.totalRecords != totalRecordCount {
                    generateAndPersistSummarySnapshot()
                }
                rebuildDirectorySkeleton(preferCache: true)
                resetSearchPaginationAndMaybeReload()
                if !canMutateHistoryData {
                    showingStorageModeAlert = true
                }
                AppSettingsCloudSync.shared.refreshActivationState()
                HistoryRecordTapActionMigration.migrateIfNeeded()
                scheduleBackgroundDedupIfNeeded(reason: "app launch")
                consumeSearchRequest()
            }
            .onChange(of: visibleDayKeys) { _, _ in
                applyDefaultExpansion(reset: false)
            }
            .onChange(of: defaultExpandLevelRaw) { _, _ in
                applyDefaultExpansion(reset: true)
            }
            .onChange(of: advancedSearchEnabled) { _, enabled in
                if !enabled {
                    searchFilter = HistorySearchFilter()
                    naturalSearchRequest = ""
                    showingSearchFilters = false
                }
                resetSearchPaginationAndMaybeReload()
            }
            .onChange(of: selectedTab) { _, tab in
                lastSelectedTabRaw = tab.rawValue
                if tab == .library, isSearching, searchResults.isEmpty {
                    resetSearchPaginationAndMaybeReload()
                }
                if tab == .library, !directoryCountsAreComplete, !isDirectoryLoading {
                    rebuildDirectorySkeleton(preferCache: true)
                }
            }
            .onChange(of: searchText) { _, _ in
                // Search results belong to the library root, not a previously
                // selected year that the new query may no longer contain.
                libraryNavigationPath.removeAll()
                scheduleSearchReload()
            }
            .onChange(of: searchFilter) { _, _ in
                libraryNavigationPath.removeAll()
                scheduleSearchReload()
            }
            .onChange(of: searchRequests.pending?.id) { _, _ in consumeSearchRequest() }
            .onChange(of: isImporting) { _, _ in consumeSearchRequest() }
            .onChange(of: isPreparingExport) { _, _ in consumeSearchRequest() }
            .onChange(of: isFileImporterPresented) { _, _ in consumeSearchRequest() }
            .onChange(of: isFileExporterPresented) { _, _ in consumeSearchRequest() }
            .onChange(of: showingImportPasswordPrompt) { _, _ in consumeSearchRequest() }
            .onChange(of: persistenceBackend) { _, _ in
                if !canMutateHistoryData {
                    showingStorageModeAlert = true
                }
                scheduleBackgroundDedupIfNeeded(reason: "backend changed")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    scheduleBackgroundDedupIfNeeded(reason: "app became active")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                scheduleBackgroundDedupIfNeeded(reason: "remote change")
            }
            .onDisappear {
                summaryGenerationTask?.cancel()
                directoryBuildTask?.cancel()
                importTask?.cancel()
                if !isImporting {
                    cleanupPendingEncryptedImport()
                }
                exportPreparationTask?.cancel()
                backgroundDedupTask?.cancel()
                searchReloadTask?.cancel()
                searchLoadTask?.cancel()
                derivedRefreshTask?.cancel()
            }
    }

}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, SummarySnapshot.self], inMemory: true)
}
