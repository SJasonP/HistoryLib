import SwiftUI

extension ContentView {
    var shouldEnforceCloudWriteProtection: Bool {
        enableICloudSync
    }

    /// The persistence backend is selected once, when the store is created at
    /// launch. If the saved iCloud Sync setting no longer matches the mode the
    /// store was actually built with, a relaunch is required before the setting
    /// can take effect.
    var pendingSyncRelaunch: Bool {
        enableICloudSync != launchICloudEnabled
    }

    var canMutateHistoryData: Bool {
        // Block writes until a relaunch reconciles the store with the setting,
        // so the active store never receives writes that contradict the chosen
        // mode (e.g. writing to a CloudKit store after sync was turned off).
        if pendingSyncRelaunch {
            return false
        }
        return !shouldEnforceCloudWriteProtection || persistenceBackend == "cloudKit"
    }

    var storageModeMessage: String {
        if pendingSyncRelaunch {
            return enableICloudSync
                ? String(localized: "iCloud Sync was turned on. Relaunch HistoryLib to apply the change. History changes are blocked until then so on-device data does not diverge.")
                : String(localized: "iCloud Sync was turned off. Relaunch HistoryLib to apply the change. History changes are blocked until then so on-device data does not diverge.")
        }

        if !shouldEnforceCloudWriteProtection {
            return String(localized: "iCloud sync is disabled in Settings. History changes are stored locally on this device.")
        }

        if persistenceBackend == "cloudKit" {
            return String(localized: "iCloud sync is on.")
        }

        return String(localized: "iCloud is currently unavailable. Changes are paused so your history stays consistent across your devices.")
    }

    var storageModeBannerText: String {
        if pendingSyncRelaunch {
            return String(localized: "Relaunch required to apply the iCloud Sync change. History changes are blocked.")
        }
        return String(localized: "iCloud unavailable. Changes are paused.")
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
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldShowDirectSearchResults: Bool {
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
        if isIPhone {
            AnyView(
                TabView(selection: $selectedTab) {
                    Tab("Summary", systemImage: "square.grid.2x2.fill", value: AppTab.summary) {
                        summaryContainer
                    }

                    Tab("Manage", systemImage: "slider.horizontal.3", value: AppTab.manage) {
                        manageContainer
                    }

                    Tab(
                        "Search",
                        systemImage: "magnifyingglass",
                        value: AppTab.library,
                        role: .search
                    ) {
                        libraryContainer
#if os(iOS)
                        .searchToolbarBehavior(.minimize)
#endif
                        .searchable(text: $searchText, prompt: "Search keywords")
                    }
                }
            )
        } else {
            AnyView(
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
            )
        }
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
#if os(iOS)
        if isIPad {
            AnyView(
                navigationContainer(title: "Library") {
                    libraryContent
                }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search keywords"
                )
            )
        } else {
            AnyView(
                navigationContainer(title: "Library") {
                    libraryContent
                }
            )
        }
#else
        navigationContainer(title: "Library") {
            libraryContent
                .searchable(text: $searchText, prompt: "Search keywords")
        }
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
            onLoadMoreSearchResults: loadNextSearchPage
        )
    }

    var manageContainer: some View {
        navigationContainer(title: "Manage") {
            ManageView(
                isSyncing: isSyncing,
                isPreparingExport: isPreparingExport,
                enableDelete: enableDelete,
                isICloudSyncEnabled: enableICloudSync,
                canMutateHistoryData: canMutateHistoryData,
                oldestRecordDate: oldestRecordDate,
                newestRecordDate: newestRecordDate,
                onImportAutoDetect: startImportAutoDetect,
                onImportAsSafari: startImportAsSafari,
                onImportAsHistoryLib: startImportAsHistoryLib,
                onRetryICloudSync: retryICloudSync,
                onExport: exportHistory,
                onClearCache: clearFaviconCache,
                onBatchDelete: deleteRecordsInRange,
                onCountRecordsInRange: countRecords
            )
        }
    }

    var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            exportProgressPanel
            .padding(.horizontal, 24)
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
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            importProgressPanel
            .padding(.horizontal, 24)
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
                startImportAutoDetect()
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

    var isIPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
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
