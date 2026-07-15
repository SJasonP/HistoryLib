import Foundation
import SwiftData

extension ContentView {
    /// Rebuilds the year/month/day directory skeleton and per-day counts.
    ///
    /// When `preferCache` is set (app launch) and a valid on-device count cache
    /// exists, the directory is restored from it instantly with no store scan.
    /// Otherwise the store is scanned in chunks, counts are accumulated, and the
    /// result is written back to the cache. Callers that follow a mutation pass
    /// `preferCache: false` so the cache is recomputed from the changed store.
    func rebuildDirectorySkeleton(preferCache: Bool = false) {
        directoryBuildTask?.cancel()
        directoryBuildGeneration += 1
        let generation = directoryBuildGeneration

        isDirectoryLoading = true
        directoryCountsAreComplete = false
        directoryDayStarts.removeAll(keepingCapacity: false)
        clearDayCaches()

        if preferCache, loadDirectoryFromCache() {
            isDirectoryLoading = false
            return
        }

        directoryBuildTask = Task { @MainActor in
            var discoveredDaySet: Set<Date> = []
            var discoveredDays: [Date] = []
            var counts: [Date: Int] = [:]
            var fetchOffset = 0

            do {
                while !Task.isCancelled {
                    var descriptor = FetchDescriptor<Item>(
                        sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
                    )
                    descriptor.fetchLimit = directoryScanChunkSize
                    descriptor.fetchOffset = fetchOffset

                    let batch = try modelContext.fetch(descriptor)
                    if batch.isEmpty {
                        break
                    }

                    for item in batch {
                        let dayStart = calendar.startOfDay(for: item.visitedAt)
                        if discoveredDaySet.insert(dayStart).inserted {
                            discoveredDays.append(dayStart)
                        }
                        counts[dayStart, default: 0] += 1
                    }

                    if generation == directoryBuildGeneration {
                        directoryDayStarts = discoveredDays
                    }

                    fetchOffset += batch.count
                    if batch.count < directoryScanChunkSize {
                        break
                    }

                    await Task.yield()
                }
            } catch {
                if !Task.isCancelled, generation == directoryBuildGeneration {
                    deleteFeedbackMessage = String(localized: "Failed to load directory: \(error.localizedDescription)")
                    showingDeleteFeedback = true
                    isDirectoryLoading = false
                }
                return
            }

            if generation == directoryBuildGeneration, !Task.isCancelled {
                // Publish the full, exact counts and cache them for next launch.
                dayItemCounts = counts
                directoryCountsAreComplete = true
                isDirectoryLoading = false
                persistDirectoryCountCache(dayCounts: counts)
            }
        }
    }

    /// Restores the directory skeleton and per-day counts from the on-device
    /// cache. Returns `false` (so the caller falls back to a full scan) when the
    /// cache is missing, was written by a different schema version or time zone,
    /// or no longer matches the live store's record count.
    func loadDirectoryFromCache() -> Bool {
        guard let snapshot = DirectoryCountCache.load(),
              snapshot.schemaVersion == DirectoryCountCache.schemaVersion,
              snapshot.timeZoneIdentifier == TimeZone.current.identifier else {
            return false
        }

        guard let liveCount = try? modelContext.fetchCount(FetchDescriptor<Item>()),
              liveCount == snapshot.totalCount else {
            return false
        }

        var counts: [Date: Int] = [:]
        var days: [Date] = []
        counts.reserveCapacity(snapshot.days.count)
        for entry in snapshot.days where entry.count > 0 {
            let dayStart = Date(timeIntervalSince1970: TimeInterval(entry.day))
            counts[dayStart] = entry.count
            days.append(dayStart)
        }
        days.sort(by: >)

        directoryDayStarts = days
        dayItemCounts = counts
        directoryCountsAreComplete = true
        return true
    }

    /// Writes the given day → count map to the on-device cache.
    func persistDirectoryCountCache(dayCounts: [Date: Int]) {
        let total = dayCounts.values.reduce(0, +)
        let entries = dayCounts.map { dayStart, count in
            DayCountEntry(day: Int64(dayStart.timeIntervalSince1970), count: count)
        }
        DirectoryCountCache.save(
            DirectoryCountSnapshot(
                schemaVersion: DirectoryCountCache.schemaVersion,
                timeZoneIdentifier: TimeZone.current.identifier,
                totalCount: total,
                days: entries
            )
        )
    }

    /// Re-persists the cache from live in-memory counts after an incremental
    /// change (e.g. a single-record delete). Skipped while counts are still being
    /// built, since the following full scan will persist an accurate cache.
    func persistDirectoryCountCacheFromStateIfComplete() {
        guard directoryCountsAreComplete else { return }
        persistDirectoryCountCache(dayCounts: dayItemCounts)
    }

    func clearDayCaches() {
        let daysToInvalidate = Set(dayItemLoadGenerations.keys)
            .union(loadingDayItems)
            .union(dayLoadedItems.keys)
        for dayStart in daysToInvalidate {
            dayItemLoadGenerations[dayStart, default: 0] += 1
        }

        dayItemCounts.removeAll(keepingCapacity: false)
        loadingDayCounts.removeAll(keepingCapacity: false)
        dayLoadedItems.removeAll(keepingCapacity: false)
        dayItemOffsets.removeAll(keepingCapacity: false)
        dayHasMoreItems.removeAll(keepingCapacity: false)
        loadingDayItems.removeAll(keepingCapacity: false)
    }

    func dayCount(for dayStart: Date) -> Int? {
        if isSearching, !shouldShowDirectSearchResults {
            return groupedSearchDayItems[dayStart]?.count ?? 0
        }
        return dayItemCounts[dayStart]
    }

    func dayItems(for dayStart: Date) -> [Item] {
        if isSearching, !shouldShowDirectSearchResults {
            return groupedSearchDayItems[dayStart] ?? []
        }
        return dayLoadedItems[dayStart] ?? []
    }

    func dayHasMoreItems(for dayStart: Date) -> Bool {
        if isSearching, !shouldShowDirectSearchResults {
            return false
        }
        return dayHasMoreItems[dayStart] ?? false
    }

    func isDayItemsLoading(for dayStart: Date) -> Bool {
        if isSearching, !shouldShowDirectSearchResults {
            return false
        }
        return loadingDayItems.contains(dayStart)
    }

    func ensureDayCountLoaded(_ dayStart: Date) {
        if isSearching, !shouldShowDirectSearchResults {
            return
        }
        guard dayItemCounts[dayStart] == nil,
              !loadingDayCounts.contains(dayStart) else {
            return
        }

        loadingDayCounts.insert(dayStart)

        Task { @MainActor in
            defer { loadingDayCounts.remove(dayStart) }

            do {
                let (start, end) = dayRange(for: dayStart)
                let descriptor = FetchDescriptor<Item>(
                    predicate: #Predicate<Item> { item in
                        item.visitedAt >= start && item.visitedAt < end
                    }
                )
                dayItemCounts[dayStart] = try modelContext.fetchCount(descriptor)
            } catch {
                dayItemCounts[dayStart] = 0
            }
        }
    }

    func ensureDayItemsLoaded(_ dayStart: Date) {
        if isSearching, !shouldShowDirectSearchResults {
            return
        }
#if os(macOS)
        guard expandedDays.contains(dayStart) else { return }
#endif
        if dayLoadedItems[dayStart] == nil {
            dayLoadedItems[dayStart] = []
            dayItemOffsets[dayStart] = 0
            dayHasMoreItems[dayStart] = true
        }
        loadMoreDayItems(dayStart)
    }

    func loadMoreDayItems(_ dayStart: Date) {
        if isSearching, !shouldShowDirectSearchResults {
            return
        }
        guard dayHasMoreItems[dayStart, default: false],
              !loadingDayItems.contains(dayStart) else {
            return
        }

        let generation = dayItemLoadGenerations[dayStart, default: 0]
        loadingDayItems.insert(dayStart)

        Task { @MainActor in
            defer { loadingDayItems.remove(dayStart) }

            do {
                let offset = dayItemOffsets[dayStart] ?? 0
                let fetched = try fetchDayItemsPage(
                    dayStart: dayStart,
                    offset: offset,
                    limit: dayItemsPageSize
                )
                guard generation == dayItemLoadGenerations[dayStart, default: 0] else {
                    return
                }

                var items = dayLoadedItems[dayStart] ?? []
                items.append(contentsOf: fetched)
                dayLoadedItems[dayStart] = items

                dayItemOffsets[dayStart] = offset + fetched.count
                dayHasMoreItems[dayStart] = fetched.count == dayItemsPageSize

                ensureDayCountLoaded(dayStart)
            } catch {
                if generation == dayItemLoadGenerations[dayStart, default: 0] {
                    dayHasMoreItems[dayStart] = false
                }
            }
        }
    }

    func releaseDayItems(_ dayStarts: [Date]) {
        for dayStart in dayStarts {
            dayItemLoadGenerations[dayStart, default: 0] += 1
            dayLoadedItems.removeValue(forKey: dayStart)
            dayItemOffsets.removeValue(forKey: dayStart)
            dayHasMoreItems.removeValue(forKey: dayStart)
            loadingDayItems.remove(dayStart)
        }
    }

    func fetchDayItemsPage(
        dayStart: Date,
        offset: Int,
        limit: Int
    ) throws -> [Item] {
        let (start, end) = dayRange(for: dayStart)
        var descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { item in
                item.visitedAt >= start && item.visitedAt < end
            },
            sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func dayRange(for dayStart: Date) -> (Date, Date) {
        let start = calendar.startOfDay(for: dayStart)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    func dayHeaderTitle(for dayStart: Date) -> String {
        if calendar.isDateInToday(dayStart) {
            return String(localized: "Today")
        }
        if calendar.isDateInYesterday(dayStart) {
            return String(localized: "Yesterday")
        }
        return dayStart.formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.abbreviated)
                .day(.twoDigits)
                .weekday(.wide)
        )
    }

    func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    func monthHeaderTitle(for monthStart: Date) -> String {
        monthStart.formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.wide)
        )
    }

    func applyDefaultExpansion(reset: Bool) {
        if reset {
            expandedYears.removeAll()
            expandedMonths.removeAll()
            expandedDays.removeAll()
        }

        switch defaultExpandLevel {
        case .none:
            break
        case .year:
            expandedYears.formUnion(yearGroups.map(\.year))
        case .month:
            expandedYears.formUnion(yearGroups.map(\.year))
            expandedMonths.formUnion(yearGroups.flatMap(\.monthGroups).map(\.monthStart))
        case .day:
            expandedYears.formUnion(yearGroups.map(\.year))
            expandedMonths.formUnion(yearGroups.flatMap(\.monthGroups).map(\.monthStart))
            expandedDays.formUnion(yearGroups.flatMap(\.monthGroups).flatMap(\.dayGroups).map(\.dayStart))
        }
    }
}
