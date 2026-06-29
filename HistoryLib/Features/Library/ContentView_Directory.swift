import Foundation
import SwiftData

extension ContentView {
    func rebuildDirectorySkeleton() {
        directoryBuildTask?.cancel()
        directoryBuildGeneration += 1
        let generation = directoryBuildGeneration

        isDirectoryLoading = true
        directoryDayStarts.removeAll(keepingCapacity: false)
        clearDayCaches()

        directoryBuildTask = Task { @MainActor in
            var discoveredDaySet: Set<Date> = []
            var discoveredDays: [Date] = []
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
                }
            }

            if generation == directoryBuildGeneration {
                isDirectoryLoading = false
            }
        }
    }

    func clearDayCaches() {
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

                var items = dayLoadedItems[dayStart] ?? []
                items.append(contentsOf: fetched)
                dayLoadedItems[dayStart] = items

                dayItemOffsets[dayStart] = offset + fetched.count
                dayHasMoreItems[dayStart] = fetched.count == dayItemsPageSize

                ensureDayCountLoaded(dayStart)
            } catch {
                dayHasMoreItems[dayStart] = false
            }
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
