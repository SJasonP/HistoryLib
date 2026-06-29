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
    @AppStorage("open_record_in_browser_on_click") var openRecordInBrowserOnDoubleClick = true
    @AppStorage("default_expand_level") var defaultExpandLevelRaw = HistoryDefaultExpandLevel.day.rawValue
    @AppStorage("show_direct_search_results_on_iphone") var showDirectSearchResultsOnIPhone = true
    @AppStorage("enable_icloud_sync") var enableICloudSync = false
    @AppStorage("last_selected_tab") var lastSelectedTabRaw = AppTab.summary.rawValue
    @AppStorage("persistence_backend") var persistenceBackend = "unknown"
    @AppStorage("persistence_error") var persistenceError = ""
    @AppStorage("persistence_launch_icloud_enabled") var launchICloudEnabled = false

#if os(macOS)
    @Environment(\.openSettings) var openSettings
#endif

    @State var isFileImporterPresented = false
    @State var importFormatPreference: HistoryImportFormatPreference = .automatic
    @State var isFileExporterPresented = false
    @State var searchText = ""
    @State var selectedTab: AppTab = .summary
    @State var expandedYears: Set<Int> = []
    @State var expandedMonths: Set<Date> = []
    @State var expandedDays: Set<Date> = []
    @State var importFeedbackMessage = ""
    @State var showingImportFeedback = false
    @State var isSyncing = false
    @State var syncFeedbackMessage = ""
    @State var showingSyncFeedback = false
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
    @State var isCancellingImport = false
    @State var importTask: Task<Void, Never>?

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

    @State var dayItemCounts: [Date: Int] = [:]
    @State var loadingDayCounts: Set<Date> = []
    @State var dayLoadedItems: [Date: [Item]] = [:]
    @State var dayItemOffsets: [Date: Int] = [:]
    @State var dayHasMoreItems: [Date: Bool] = [:]
    @State var loadingDayItems: Set<Date> = []

    @State var totalRecordCount = 0
    @State var oldestRecordDate: Date?
    @State var newestRecordDate: Date?
    @State var latestSummarySnapshot: SummarySnapshot?
    @State var summaryGenerationToken = 0
    @State var summaryGenerationTask: Task<Void, Never>?
    @State var showingStorageModeAlert = false
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
            .alert("Import Result", isPresented: $showingImportFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importFeedbackMessage)
            }
            .alert("Sync Result", isPresented: $showingSyncFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncFeedbackMessage)
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
            .alert("Cloud Sync Unavailable", isPresented: $showingStorageModeAlert) {
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
                rebuildDirectorySkeleton()
                resetSearchPaginationAndMaybeReload()
                if shouldEnforceCloudWriteProtection && !canMutateHistoryData {
                    showingStorageModeAlert = true
                }
                AppSettingsCloudSync.shared.refreshActivationState()
                scheduleBackgroundDedupIfNeeded(reason: "app launch")
            }
            .onChange(of: visibleDayKeys) { _, _ in
                applyDefaultExpansion(reset: false)
            }
            .onChange(of: defaultExpandLevelRaw) { _, _ in
                applyDefaultExpansion(reset: true)
            }
            .onChange(of: selectedTab) { _, tab in
                lastSelectedTabRaw = tab.rawValue
                if tab == .library, isSearching, searchResults.isEmpty {
                    resetSearchPaginationAndMaybeReload()
                }
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearchReload()
            }
            .onChange(of: persistenceBackend) { _, backend in
                if shouldEnforceCloudWriteProtection, backend != "cloudKit" {
                    showingStorageModeAlert = true
                }
                scheduleBackgroundDedupIfNeeded(reason: "backend changed")
            }
            .onChange(of: enableICloudSync) { _, _ in
                AppSettingsCloudSync.shared.refreshActivationState()
                if !canMutateHistoryData {
                    showingStorageModeAlert = true
                }
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
                exportPreparationTask?.cancel()
                backgroundDedupTask?.cancel()
                searchReloadTask?.cancel()
                searchLoadTask?.cancel()
                derivedRefreshTask?.cancel()
                importTask?.cancel()
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, SummarySnapshot.self], inMemory: true)
}
