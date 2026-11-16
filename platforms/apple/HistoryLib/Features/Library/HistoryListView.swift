import SwiftUI

/// A value route outlives a compact/regular root-list transition. A closure
/// destination attached only to the compact list would disappear on unfolding.
struct HistoryYearDestination: Hashable {
    let year: Int
}

struct HistoryMonthID: Hashable {
    let value: Date
}

struct HistoryDayID: Hashable {
    let value: Date
}

struct HistoryMonthGroup: Identifiable {
    let monthStart: Date
    let title: String
    let dayGroups: [HistoryDayGroup]

    var id: HistoryMonthID { HistoryMonthID(value: monthStart) }
    var dayStarts: [Date] { dayGroups.map(\.dayStart) }
}

struct HistoryYearGroup: Identifiable {
    let year: Int
    let title: String
    let monthGroups: [HistoryMonthGroup]

    var id: Int { year }
}

struct HistoryDayGroup: Identifiable {
    let dayStart: Date
    let title: String

    var id: HistoryDayID { HistoryDayID(value: dayStart) }
}

enum HistoryHierarchyExpansion {
    static func collapse(
        _ yearGroup: HistoryYearGroup,
        years: inout Set<Int>,
        months: inout Set<Date>,
        days: inout Set<Date>
    ) -> [Date] {
        let descendantDays = yearGroup.monthGroups.flatMap(\.dayStarts)
        years.remove(yearGroup.year)
        months.subtract(yearGroup.monthGroups.map(\.monthStart))
        days.subtract(descendantDays)
        return descendantDays
    }

    static func collapse(
        _ monthGroup: HistoryMonthGroup,
        months: inout Set<Date>,
        days: inout Set<Date>
    ) -> [Date] {
        months.remove(monthGroup.monthStart)
        days.subtract(monthGroup.dayStarts)
        return monthGroup.dayStarts
    }
}

struct HistoryListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let yearGroups: [HistoryYearGroup]
    let flatSearchItems: [Item]
    let isSearching: Bool
    let showDirectSearchResults: Bool
    let isDirectoryLoading: Bool
    @Binding var expandedYears: Set<Int>
    @Binding var expandedMonths: Set<Date>
    @Binding var expandedDays: Set<Date>
    let showTime: Bool
    let showSiteIcons: Bool
    let enableDelete: Bool
    let openTapCount: Int
    let canLoadMoreSearchResults: Bool
    let isLoadingSearchResults: Bool
    let dayCountProvider: (Date) -> Int?
    let dayItemsProvider: (Date) -> [Item]
    let dayHasMoreProvider: (Date) -> Bool
    let dayIsLoadingProvider: (Date) -> Bool
    let onOpenItem: (Item) -> Void
    let onDeleteItem: (Item) -> Void
    let onCopyURL: (String) -> Void
    let onEnsureDayCount: (Date) -> Void
    let onEnsureDayItems: (Date) -> Void
    let onLoadMoreDayItems: (Date) -> Void
    let onReleaseDayItems: ([Date]) -> Void
    let onLoadMoreSearchResults: () -> Void

    var body: some View {
        Group {
            if showDirectSearchResults {
                directSearchResultsList
            } else if isSearching {
                groupedSearchResultsView
            } else if yearGroups.isEmpty {
                if isDirectoryLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading directory...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No History Records",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Import Safari or Chrome Takeout JSON/folder/ZIP files, or a HistoryLib .hlz archive.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if usesCompactNavigation {
                compactNavigationList
            } else {
                desktopGroupedList
            }
        }
        .navigationDestination(for: HistoryYearDestination.self) { destination in
            if let yearGroup = yearGroups.first(where: { $0.year == destination.year }) {
                HistoryMonthNavigationList(
                    yearGroup: yearGroup,
                    showTime: showTime,
                    showSiteIcons: showSiteIcons,
                    enableDelete: enableDelete,
                    openTapCount: openTapCount,
                    dayCountProvider: dayCountProvider,
                    dayItemsProvider: dayItemsProvider,
                    dayHasMoreProvider: dayHasMoreProvider,
                    dayIsLoadingProvider: dayIsLoadingProvider,
                    onOpenItem: onOpenItem,
                    onDeleteItem: onDeleteItem,
                    onCopyURL: onCopyURL,
                    onEnsureDayCount: onEnsureDayCount,
                    onEnsureDayItems: onEnsureDayItems,
                    onLoadMoreDayItems: onLoadMoreDayItems
                )
            }
        }
    }

    @ViewBuilder
    private var groupedSearchResultsView: some View {
        if flatSearchItems.isEmpty {
            if canLoadMoreSearchResults || isLoadingSearchResults {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    onLoadMoreSearchResults()
                }
            } else {
                ContentUnavailableView(
                    "No Matching Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different keyword.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if usesCompactNavigation {
            compactNavigationList
        } else {
            desktopGroupedList
        }
    }

    private var desktopGroupedList: some View {
        List {
            ForEach(yearGroups) { yearGroup in
                hierarchyRow(
                    title: yearGroup.title,
                    count: groupCountLabel(
                        for: yearGroup.monthGroups.flatMap(\.dayStarts)
                    ),
                    level: 0,
                    isExpanded: expandedYears.contains(yearGroup.year)
                ) {
                    toggleYear(yearGroup)
                }

                if expandedYears.contains(yearGroup.year) {
                    ForEach(yearGroup.monthGroups) { monthGroup in
                        hierarchyRow(
                            title: monthGroup.title,
                            count: groupCountLabel(for: monthGroup.dayStarts),
                            level: 1,
                            isExpanded: expandedMonths.contains(monthGroup.monthStart)
                        ) {
                            toggleMonth(monthGroup)
                        }

                        if expandedMonths.contains(monthGroup.monthStart) {
                            ForEach(monthGroup.dayGroups) { dayGroup in
                                hierarchyRow(
                                    title: dayGroup.title,
                                    count: dayCountLabel(for: dayGroup.dayStart),
                                    level: 2,
                                    isExpanded: expandedDays.contains(dayGroup.dayStart)
                                ) {
                                    toggleDay(dayGroup.dayStart)
                                }
                                .onAppear {
                                    onEnsureDayCount(dayGroup.dayStart)
                                }

                                if expandedDays.contains(dayGroup.dayStart) {
                                    dayContent(for: dayGroup.dayStart)
                                        .padding(.leading, 48)
                                }
                            }
                        }
                    }
                }
            }

            if isSearching && (canLoadMoreSearchResults || isLoadingSearchResults) {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .task {
                    onLoadMoreSearchResults()
                }
                .listRowSeparator(.hidden)
            }
        }
        .animation(hierarchyAnimation, value: expandedYears)
        .animation(hierarchyAnimation, value: expandedMonths)
        .animation(hierarchyAnimation, value: expandedDays)
    }

    private func hierarchyRow(
        title: String,
        count: String? = nil,
        level: Int,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(title)
                    .font(.headline)
                if let count {
                    Text("(\(count))")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(level) * 16)
        .accessibilityLabel(title)
        .accessibilityValue(String(localized: isExpanded ? "Expanded" : "Collapsed"))
    }

    @ViewBuilder
    private func dayContent(for dayStart: Date) -> some View {
        let items = dayItemsProvider(dayStart)
        let isLoading = dayIsLoadingProvider(dayStart)

        if items.isEmpty {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.vertical, 6)
                    Text("Loading records...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No records loaded.")
                    .foregroundStyle(.secondary)
                    .onAppear {
                        onEnsureDayItems(dayStart)
                    }
            }
        } else {
            ForEach(items) { item in
                HistoryRecordRow(
                    item: item,
                    showTime: showTime,
                    showSiteIcons: showSiteIcons,
                    forceShowDate: false,
                    openTapCount: openTapCount,
                    enableDelete: enableDelete,
                    onOpenItem: onOpenItem,
                    onDeleteItem: onDeleteItem,
                    onCopyURL: onCopyURL
                )
            }
        }

        if dayHasMoreProvider(dayStart) {
            Button {
                onLoadMoreDayItems(dayStart)
            } label: {
                if isLoading {
                    Label("Loading more records", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Text("Load More")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isLoading ? "Loading more records" : "Load More")
        }
    }

    private var directSearchResultsList: some View {
        Group {
            if flatSearchItems.isEmpty {
                groupedSearchResultsView
            } else {
                List {
                    ForEach(flatSearchItems) { item in
                        HistoryRecordRow(
                            item: item,
                            showTime: false,
                            showSiteIcons: showSiteIcons,
                            forceShowDate: true,
                            openTapCount: openTapCount,
                            enableDelete: enableDelete,
                            onOpenItem: onOpenItem,
                            onDeleteItem: onDeleteItem,
                            onCopyURL: onCopyURL
                        )
                    }

                    if canLoadMoreSearchResults || isLoadingSearchResults {
                        Label("Loading more records", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                        .task {
                            onLoadMoreSearchResults()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }

    private var compactNavigationList: some View {
        List {
            ForEach(yearGroups) { yearGroup in
                NavigationLink(value: HistoryYearDestination(year: yearGroup.year)) {
                    HStack {
                        Text(yearGroup.title)
                            .font(.headline)
                        Spacer()
                        let count = groupCountLabel(for: yearGroup.monthGroups.flatMap(\.dayGroups).map(\.dayStart))
                        Text(count)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                count == "..." ? String(localized: "Record count unavailable") : count
                            )
                    }
                }
            }

            if isSearching && (canLoadMoreSearchResults || isLoadingSearchResults) {
                Label("Loading more records", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
                .task {
                    onLoadMoreSearchResults()
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    private var usesCompactNavigation: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private func dayCountLabel(for dayStart: Date) -> String {
        if let count = dayCountProvider(dayStart) {
            return String(count)
        }
        return "..."
    }

    private func groupCountLabel(for dayStarts: [Date]) -> String {
        var total = 0
        for dayStart in dayStarts {
            guard let dayCount = dayCountProvider(dayStart) else {
                return "..."
            }
            total += dayCount
        }
        return String(total)
    }

    private func toggleYear(_ yearGroup: HistoryYearGroup) {
        withHierarchyAnimation {
            if expandedYears.contains(yearGroup.year) {
                let dayStarts = HistoryHierarchyExpansion.collapse(
                    yearGroup,
                    years: &expandedYears,
                    months: &expandedMonths,
                    days: &expandedDays
                )
                onReleaseDayItems(dayStarts)
            } else {
                expandedYears.insert(yearGroup.year)
            }
        }
    }

    private func toggleMonth(_ monthGroup: HistoryMonthGroup) {
        withHierarchyAnimation {
            if expandedMonths.contains(monthGroup.monthStart) {
                let dayStarts = HistoryHierarchyExpansion.collapse(
                    monthGroup,
                    months: &expandedMonths,
                    days: &expandedDays
                )
                onReleaseDayItems(dayStarts)
            } else {
                expandedMonths.insert(monthGroup.monthStart)
            }
        }
    }

    private func toggleDay(_ day: Date) {
        withHierarchyAnimation {
            if expandedDays.contains(day) {
                expandedDays.remove(day)
                onReleaseDayItems([day])
            } else {
                expandedDays.insert(day)
                onEnsureDayItems(day)
                onEnsureDayCount(day)
            }
        }
    }

    private func withHierarchyAnimation(_ updates: () -> Void) {
        withAnimation(hierarchyAnimation, updates)
    }

    private var hierarchyAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }
}
