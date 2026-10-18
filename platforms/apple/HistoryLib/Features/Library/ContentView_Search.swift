import Foundation
import SwiftData

extension ContentView {
    func scheduleSearchReload() {
        searchReloadTask?.cancel()
        searchReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            resetSearchPaginationAndMaybeReload()
        }
    }

    func resetSearchPaginationAndMaybeReload() {
        searchLoadTask?.cancel()
        searchResults.removeAll(keepingCapacity: false)
        searchScanOffset = 0
        isLoadingSearchResults = false
        hasMoreSearchResults = isSearching
        if isSearching {
            loadNextSearchPage()
        }
    }

    func loadNextSearchPage() {
        guard isSearching, !isLoadingSearchResults, hasMoreSearchResults else {
            return
        }

        isLoadingSearchResults = true
        let query = normalizedSearchText
        searchLoadTask = Task { @MainActor in
            defer { isLoadingSearchResults = false }
            await appendNextSearchPage(query: query)
        }
    }

    // Scans the store in chunks until a full page of matches is collected or the
    // end is reached. It yields between chunks so the UI never blocks, and it
    // never truncates a chunk's matches, so no match is silently skipped.
    private func appendNextSearchPage(query: String) async {
        guard !query.isEmpty else {
            hasMoreSearchResults = false
            return
        }

        var collected = 0

        do {
            while true {
                try Task.checkCancellation()

                var descriptor = FetchDescriptor<Item>(
                    sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
                )
                descriptor.fetchLimit = searchScanChunkSize
                descriptor.fetchOffset = searchScanOffset

                let scanned = try modelContext.fetch(descriptor)
                if scanned.isEmpty {
                    hasMoreSearchResults = false
                    return
                }

                searchScanOffset += scanned.count

                let matches = scanned.filter { item in
                    item.url.localizedCaseInsensitiveContains(query)
                        || item.title.localizedCaseInsensitiveContains(query)
                }
                if !matches.isEmpty {
                    searchResults.append(contentsOf: matches)
                    collected += matches.count
                }

                if scanned.count < searchScanChunkSize {
                    // Reached the end of the store.
                    hasMoreSearchResults = false
                    return
                }

                if collected >= searchPageSize {
                    // Page filled; keep the cursor for the next page.
                    hasMoreSearchResults = true
                    return
                }

                await Task.yield()
            }
        } catch is CancellationError {
            return
        } catch {
            hasMoreSearchResults = false
            deleteFeedbackMessage = String(localized: "Failed to load search results: \(error.localizedDescription)")
            showingDeleteFeedback = true
        }
    }
}
