import Foundation
import SwiftData

extension ContentView {
    func refreshSummaryStats() {
        do {
            let total = try modelContext.fetchCount(FetchDescriptor<Item>())
            totalRecordCount = total

            var newestDescriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
            )
            newestDescriptor.fetchLimit = 1
            newestRecordDate = try modelContext.fetch(newestDescriptor).first?.visitedAt

            var oldestDescriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .forward)]
            )
            oldestDescriptor.fetchLimit = 1
            oldestRecordDate = try modelContext.fetch(oldestDescriptor).first?.visitedAt
        } catch {
            totalRecordCount = 0
            newestRecordDate = nil
            oldestRecordDate = nil
        }
    }

    func loadLatestSummarySnapshot() {
        do {
            var descriptor = FetchDescriptor<SummarySnapshot>(
                sortBy: [SortDescriptor(\SummarySnapshot.generatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            latestSummarySnapshot = try modelContext.fetch(descriptor).first
        } catch {
            latestSummarySnapshot = nil
        }
    }

    /// Coalesced entry point for rebuilding all derived UI state after a history
    /// mutation. A burst of imports/deletes collapses into a single refresh
    /// instead of starting several overlapping full-table scans.
    func scheduleDerivedDataRefresh() {
        derivedRefreshTask?.cancel()
        derivedRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            refreshSummaryStats()
            rebuildDirectorySkeleton()
            resetSearchPaginationAndMaybeReload()
            generateAndPersistSummarySnapshot()
        }
    }

    func generateAndPersistSummarySnapshot() {
        summaryGenerationToken += 1
        let token = summaryGenerationToken
        summaryGenerationTask?.cancel()

        let generator = SummarySnapshotGenerator(
            modelContainer: modelContext.container,
            calendar: calendar,
            fetchChunkSize: directoryScanChunkSize
        )

        summaryGenerationTask = Task(priority: .utility) {
            do {
                let computed = try await generator.build()
                await MainActor.run {
                    guard !Task.isCancelled, token == summaryGenerationToken else {
                        return
                    }

                    let snapshot = SummarySnapshot(
                        generatedAt: Date(),
                        totalRecords: computed.totalRecords,
                        averagePerDay: computed.averagePerDay,
                        averagePerMonth: computed.averagePerMonth,
                        averagePerYear: computed.averagePerYear,
                        topSites: computed.topSites
                    )

                    // Update UI immediately with the latest computed summary.
                    latestSummarySnapshot = snapshot

                    do {
                        let existingSnapshots = try modelContext.fetch(FetchDescriptor<SummarySnapshot>())
                        for existing in existingSnapshots {
                            modelContext.delete(existing)
                        }

                        guard !Task.isCancelled, token == summaryGenerationToken else {
                            return
                        }

                        modelContext.insert(snapshot)
                        try modelContext.save()
                    } catch {
                        // Keep the app responsive even if summary persistence fails.
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // Keep the app responsive even if summary generation fails.
            }
        }
    }
}

private struct SummarySnapshotComputation: Sendable {
    let totalRecords: Int
    let averagePerDay: Double
    let averagePerMonth: Double
    let averagePerYear: Double
    let topSites: [SummaryTopSite]
}

private actor SummarySnapshotGenerator {
    private let modelContainer: ModelContainer
    private let calendar: Calendar
    private let fetchChunkSize: Int

    init(modelContainer: ModelContainer, calendar: Calendar, fetchChunkSize: Int) {
        self.modelContainer = modelContainer
        self.calendar = calendar
        self.fetchChunkSize = max(200, fetchChunkSize)
    }

    func build() async throws -> SummarySnapshotComputation {
        let context = ModelContext(modelContainer)
        var totalRecords = 0
        var earliestVisitedAt: Date?
        var latestVisitedAt: Date?
        var hostVisitCount: [String: Int] = [:]
        var fetchOffset = 0
        var scannedRecords = 0

        while true {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = fetchChunkSize
            descriptor.fetchOffset = fetchOffset

            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            totalRecords += batch.count

            for item in batch {
                if let earliest = earliestVisitedAt {
                    if item.visitedAt < earliest {
                        earliestVisitedAt = item.visitedAt
                    }
                } else {
                    earliestVisitedAt = item.visitedAt
                }
                if let latest = latestVisitedAt {
                    if item.visitedAt > latest {
                        latestVisitedAt = item.visitedAt
                    }
                } else {
                    latestVisitedAt = item.visitedAt
                }

                let hostKey = Self.hostKey(from: item.url)
                hostVisitCount[hostKey, default: 0] += 1
            }

            fetchOffset += batch.count
            scannedRecords += batch.count
            if batch.count < fetchChunkSize {
                break
            }

            if scannedRecords >= fetchChunkSize * 2 {
                scannedRecords = 0
                await Task.yield()
            }
        }

        let topSites = hostVisitCount
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(10)
            .map { SummaryTopSite(host: $0.key, visits: $0.value) }

        let daySpan = Self.daySpanCount(from: earliestVisitedAt, to: latestVisitedAt, calendar: calendar)
        let monthSpan = Self.monthSpanCount(from: earliestVisitedAt, to: latestVisitedAt, calendar: calendar)
        let yearSpan = Self.yearSpanCount(from: earliestVisitedAt, to: latestVisitedAt, calendar: calendar)

        let currentTotalRecords = (try? context.fetchCount(FetchDescriptor<Item>())) ?? totalRecords

        return SummarySnapshotComputation(
            totalRecords: currentTotalRecords,
            averagePerDay: Self.average(currentTotalRecords, over: daySpan),
            averagePerMonth: Self.average(currentTotalRecords, over: monthSpan),
            averagePerYear: Self.average(currentTotalRecords, over: yearSpan),
            topSites: topSites
        )
    }

    private static func hostKey(from rawURL: String) -> String {
        if let url = URL(string: rawURL),
           let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host.lowercased()
        }
        return "(unknown)"
    }

    private static func average(_ total: Int, over bucketCount: Int) -> Double {
        guard bucketCount > 0 else { return 0 }
        return Double(total) / Double(bucketCount)
    }

    private static func daySpanCount(from start: Date?, to end: Date?, calendar: Calendar) -> Int {
        guard let start, let end else { return 0 }
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let delta = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(0, delta) + 1
    }

    private static func monthSpanCount(from start: Date?, to end: Date?, calendar: Calendar) -> Int {
        guard let start, let end else { return 0 }
        let startComponents = calendar.dateComponents([.year, .month], from: start)
        let endComponents = calendar.dateComponents([.year, .month], from: end)
        guard
            let startYear = startComponents.year,
            let startMonth = startComponents.month,
            let endYear = endComponents.year,
            let endMonth = endComponents.month
        else {
            return 0
        }

        let delta = (endYear - startYear) * 12 + (endMonth - startMonth)
        return max(0, delta) + 1
    }

    private static func yearSpanCount(from start: Date?, to end: Date?, calendar: Calendar) -> Int {
        guard let start, let end else { return 0 }
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        return max(0, endYear - startYear) + 1
    }
}
