import Foundation
import SwiftData

extension ContentView {
    func scheduleSearchReload() {
        searchReloadTask?.cancel()
        searchReloadTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                resetSearchPaginationAndMaybeReload()
            }
        }
    }

    func resetSearchPaginationAndMaybeReload() {
        searchResults.removeAll(keepingCapacity: false)
        searchScanOffset = 0
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
        defer { isLoadingSearchResults = false }

        do {
            let fetched = try fetchNextSearchPage(query: normalizedSearchText)
            searchResults.append(contentsOf: fetched)
        } catch {
            hasMoreSearchResults = false
            deleteFeedbackMessage = "Failed to load search results: \(error.localizedDescription)"
            showingDeleteFeedback = true
        }
    }

    func fetchNextSearchPage(query: String) throws -> [Item] {
        guard !query.isEmpty else {
            hasMoreSearchResults = false
            return []
        }

        var matchedItems: [Item] = []
        var reachedEnd = false
        var scannedChunkCount = 0

        while matchedItems.count < searchPageSize, scannedChunkCount < maxSearchChunksPerPage {
            var descriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = searchScanChunkSize
            descriptor.fetchOffset = searchScanOffset

            let scanned = try modelContext.fetch(descriptor)
            if scanned.isEmpty {
                reachedEnd = true
                break
            }

            searchScanOffset += scanned.count

            let filtered = scanned.filter { item in
                item.url.localizedCaseInsensitiveContains(query)
                    || item.title.localizedCaseInsensitiveContains(query)
            }

            let remaining = searchPageSize - matchedItems.count
            if remaining > 0 {
                matchedItems.append(contentsOf: filtered.prefix(remaining))
            }

            if scanned.count < searchScanChunkSize {
                reachedEnd = true
                break
            }

            scannedChunkCount += 1
        }

        hasMoreSearchResults = !reachedEnd
        return matchedItems
    }
}
