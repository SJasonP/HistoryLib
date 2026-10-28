import SwiftUI
import SwiftData

extension ContentView {
    var canMutateHistoryData: Bool {
        HistoryStoragePolicy.canMutate(backend: persistenceBackend)
    }

    var storageModeAlertTitle: String {
        String(localized: "Storage Unavailable")
    }

    var storageModeMessage: String {
        String(localized: "History storage could not be opened. Changes are paused. Restart the app after resolving the storage problem.")
    }

    var storageModeBannerText: String {
        String(localized: "History storage unavailable. Changes are paused.")
    }

    var storageModeBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(storageModeBannerText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    var defaultExpandLevel: HistoryDefaultExpandLevel {
        HistoryDefaultExpandLevel(rawValue: defaultExpandLevelRaw) ?? .day
    }

    var visibleDayKeys: [Date] {
        yearGroups.flatMap { year in
            year.monthGroups.flatMap { month in
                month.dayGroups.map(\.dayStart)
            }
        }
    }

    var isSearching: Bool {
        effectiveSearchFilter.isActive
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldShowDirectSearchResults: Bool {
        // This is an existing phone-specific user preference, not a layout
        // decision. Keep the result presentation unchanged while folding.
        isIPhone && isSearching && showDirectSearchResultsOnIPhone
    }

    var groupedSearchDayItems: [Date: [Item]] {
        guard isSearching, !shouldShowDirectSearchResults else { return [:] }

        var grouped = Dictionary(grouping: searchResults) { item in
            calendar.startOfDay(for: item.visitedAt)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.visitedAt > $1.visitedAt }
        }
        return grouped
    }

    var activeDayStarts: [Date] {
        if isSearching, !shouldShowDirectSearchResults {
            return groupedSearchDayItems.keys.sorted(by: >)
        }
        return directoryDayStarts
    }

    var yearGroups: [HistoryYearGroup] {
        let dayGroups = activeDayStarts.map { dayStart in
            HistoryDayGroup(
                dayStart: dayStart,
                title: dayHeaderTitle(for: dayStart)
            )
        }

        let monthDictionary = Dictionary(grouping: dayGroups) { group in
            monthStart(for: group.dayStart)
        }

        let monthGroups = monthDictionary
            .map { monthStart, days in
                HistoryMonthGroup(
                    monthStart: monthStart,
                    title: monthHeaderTitle(for: monthStart),
                    dayGroups: days.sorted { $0.dayStart > $1.dayStart }
                )
            }

        let yearDictionary = Dictionary(grouping: monthGroups) { group in
            calendar.component(.year, from: group.monthStart)
        }

        return yearDictionary
            .map { year, months in
                HistoryYearGroup(
                    year: year,
                    title: String(year),
                    monthGroups: months.sorted { $0.monthStart > $1.monthStart }
                )
            }
            .sorted { $0.year > $1.year }
    }

    func navigationContainer<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar { topToolbar }
        }
    }

    var mainTabView: some View {
#if os(macOS)
        TabView(selection: $selectedTab) {
            summaryContainer
                .tabItem { Text("Summary") }
                .tag(AppTab.summary)

            libraryContainer
                .tabItem { Text("Library") }
                .tag(AppTab.library)

            manageContainer
                .tabItem { Text("Manage") }
                .tag(AppTab.manage)
        }
#else
        // Keep one tab/navigation tree as the window changes size. The system
        // moves the same controls between tab bar, vertical bar, and sidebar.
        TabView(selection: $selectedTab) {
            Tab("Summary", systemImage: "square.grid.2x2.fill", value: AppTab.summary) {
                summaryContainer
            }

            Tab("Manage", systemImage: "slider.horizontal.3", value: AppTab.manage) {
                manageContainer
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.library, role: .search) {
                libraryContainer
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .historySidebarPlacement()
#endif
    }

    var summaryContainer: some View {
        navigationContainer(title: "Summary") {
            SummaryView(
                snapshot: latestSummarySnapshot
            )
        }
    }

    var libraryContainer: some View {
        NavigationStack(path: $libraryNavigationPath) {
            VStack(spacing: 0) {
                if searchFilter.isActive {
                    HStack {
                        Button("Review Filters") {
                            naturalSearchRequest = ""
                            showingSearchFilters = true
                        }
                        Spacer()
                        Button("Clear Filters") { searchFilter = HistorySearchFilter() }
                    }
                    .font(.footnote)
                    .padding()
                }
                libraryContent
            }
            .navigationTitle("Library")
            .toolbar {
                topToolbar
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        naturalSearchRequest = ""
                        showingSearchFilters = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(isImporting || isPreparingExport)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search keywords")
#if os(iOS)
        .searchToolbarBehavior(.minimize)
#endif
    }

    var libraryContent: some View {
        HistoryListView(
            yearGroups: yearGroups,
            flatSearchItems: searchResults,
            isSearching: isSearching,
            showDirectSearchResults: shouldShowDirectSearchResults,
            isDirectoryLoading: isDirectoryLoading,
            expandedYears: $expandedYears,
            expandedMonths: $expandedMonths,
            expandedDays: $expandedDays,
            showTime: showHistoryTime,
            showSiteIcons: showSiteIcons,
            enableDelete: enableDelete && canMutateHistoryData,
            openTapCount: openTapCount,
            canLoadMoreSearchResults: hasMoreSearchResults,
            isLoadingSearchResults: isLoadingSearchResults,
            dayCountProvider: dayCount(for:),
            dayItemsProvider: dayItems(for:),
            dayHasMoreProvider: dayHasMoreItems(for:),
            dayIsLoadingProvider: isDayItemsLoading(for:),
            onOpenItem: openRecordInBrowserIfNeeded,
            onDeleteItem: deleteSingleRecord,
            onEnsureDayCount: ensureDayCountLoaded,
            onEnsureDayItems: ensureDayItemsLoaded,
            onLoadMoreDayItems: loadMoreDayItems,
            onReleaseDayItems: releaseDayItems,
            onLoadMoreSearchResults: loadNextSearchPage
        )
    }

    var manageContainer: some View {
        navigationContainer(title: "Manage") {
            ManageView(
                isPreparingExport: isPreparingExport,
                enableDelete: enableDelete,
                isActive: selectedTab == .manage,
                isImporting: isImporting || isFileImporterPresented || isFileExporterPresented || showingImportPasswordPrompt,
                storageModeMessage: storageModeMessage,
                canMutateHistoryData: canMutateHistoryData,
                oldestRecordDate: oldestRecordDate,
                newestRecordDate: newestRecordDate,
                onImport: startImport,
                onCountLocalRecords: { try modelContext.fetchCount(FetchDescriptor<Item>()) },
                onExport: exportHistory,
                onMeasureStorageUsage: measureClearCacheStorageUsage,
                onClearCache: clearCaches,
                onBatchDelete: deleteRecordsInRange,
                onCountRecordsInRange: countRecords
            )
        }
    }

    var exportProgressOverlay: some View {
        TransferProgressOverlay {
            exportProgressPanel
        }
    }

    var exportProgressPanel: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportProgressFraction)
                .progressViewStyle(.linear)

            Text(exportProgressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                cancelExportPreparation()
            } label: {
                if isCancellingExport {
                    Label("Cancelling...", systemImage: "hourglass")
                } else {
                    Label("Cancel Export", systemImage: "xmark.circle")
                }
            }
            .disabled(isCancellingExport)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .exportProgressSurface()
    }

    var importProgressOverlay: some View {
        TransferProgressOverlay {
            importProgressPanel
        }
    }

    var importProgressPanel: some View {
        VStack(spacing: 16) {
            if let fraction = importProgressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            Text(importProgressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                cancelImport()
            } label: {
                if isCancellingImport {
                    Label("Cancelling...", systemImage: "hourglass")
                } else {
                    Label("Cancel Import", systemImage: "xmark.circle")
                }
            }
            .disabled(isCancellingImport)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .exportProgressSurface()
    }

    @ToolbarContentBuilder
    var topToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                startImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(!canMutateHistoryData)
        }

        ToolbarItem {
#if os(macOS)
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
#else
            Button {
                openSystemAppSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
#endif
        }
    }

    var openTapCount: Int {
#if os(macOS)
        return 2
#else
        return 1
#endif
    }

    var isIPhone: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    func restoredTab(from rawValue: String) -> AppTab {
        if rawValue == "historySearch" {
            return .library
        }
        return AppTab(rawValue: rawValue) ?? .summary
    }
}
