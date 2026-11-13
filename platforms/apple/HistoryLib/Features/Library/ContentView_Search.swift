import Foundation

extension ContentView {
    var effectiveSearchFilter: HistorySearchFilter {
        var filter = searchFilter
        if !normalizedSearchText.isEmpty { filter.keywords.append(normalizedSearchText) }
        return filter
    }

    func scheduleSearchReload() {
        searchReloadTask?.cancel()
        searchLoadTask?.cancel()
        searchGeneration += 1
        searchResults.removeAll(keepingCapacity: true)
        searchScanOffset = 0
        hasMoreSearchResults = isSearching
        // Reserve loading while debouncing so an appearing pagination sentinel
        // cannot start the new query at the old query's cursor.
        isLoadingSearchResults = isSearching
        searchReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            resetSearchPaginationAndMaybeReload()
        }
    }

    func resetSearchPaginationAndMaybeReload() {
        searchLoadTask?.cancel()
        searchGeneration += 1
        searchResults.removeAll(keepingCapacity: false)
        searchScanOffset = 0
        isLoadingSearchResults = false
        hasMoreSearchResults = isSearching
        if isSearching { loadNextSearchPage() }
    }

    func loadNextSearchPage() {
        guard isSearching, !isLoadingSearchResults, hasMoreSearchResults else { return }
        isLoadingSearchResults = true
        let filter = effectiveSearchFilter
        let offset = searchScanOffset
        let generation = searchGeneration
        searchLoadTask = Task { @MainActor in
            defer {
                if generation == searchGeneration { isLoadingSearchResults = false }
            }
            do {
                let page = try await HistorySearchEngine.page(
                    in: modelContext, filter: filter, offset: offset,
                    scanLimit: searchScanChunkSize, targetMatches: searchPageSize
                )
                try Task.checkCancellation()
                guard generation == searchGeneration, filter == effectiveSearchFilter else { return }
                searchResults.append(contentsOf: page.records)
                searchScanOffset = page.nextOffset
                hasMoreSearchResults = page.hasMore
            } catch is CancellationError {
                return
            } catch {
                guard generation == searchGeneration else { return }
                hasMoreSearchResults = false
                searchErrorMessage = String(localized: "Search could not be completed. Please try again.")
                showingSearchError = true
            }
        }
    }

    func applySearchFilter(_ filter: HistorySearchFilter) {
        searchText = ""
        searchFilter = filter
        libraryNavigationPath.removeAll()
        selectedTab = .library
    }

    func submitSearch() {
        guard isAdvancedSearchEnabled else { return }
        let request = normalizedSearchText
        guard !request.isEmpty else { return }
        guard NaturalLanguageHistorySearch().isAvailable else { return }
        naturalSearchRequest = request
        showingSearchFilters = true
    }

    func consumeSearchRequest() {
        guard !isFileImporterPresented, !isFileExporterPresented, !showingImportPasswordPrompt,
              !showingSearchFilters,
              let request = searchRequests.consume(isBusy: isImporting || isPreparingExport) else { return }
        selectedTab = .library
        libraryNavigationPath.removeAll()
        if request.mode == .naturalLanguage,
           isAdvancedSearchEnabled,
           HistorySearchFeatureFlags.appleIntelligenceAndSiriEnabled {
            naturalSearchRequest = request.query
            showingSearchFilters = true
        } else {
            searchFilter = HistorySearchFilter()
            searchText = request.query
        }
    }
}
