import SwiftUI

#if os(iOS)
import UIKit
#endif

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

struct HistoryListView: View {
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
    let onEnsureDayCount: (Date) -> Void
    let onEnsureDayItems: (Date) -> Void
    let onLoadMoreDayItems: (Date) -> Void
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
                        description: Text("Import Safari JSON/folder/ZIP files or a HistoryLib .hlz archive.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if isIPhone {
                iPhoneNavigationList
            } else {
                desktopGroupedList
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
        } else if isIPhone {
            iPhoneNavigationList
        } else {
            desktopGroupedList
        }
    }

    private var desktopGroupedList: some View {
        List {
            ForEach(yearGroups) { yearGroup in
                DisclosureGroup(
                    isExpanded: bindingForYear(yearGroup.year)
                ) {
                    ForEach(yearGroup.monthGroups) { monthGroup in
                        DisclosureGroup(
                            isExpanded: bindingForMonth(monthGroup.monthStart)
                        ) {
                            ForEach(monthGroup.dayGroups) { dayGroup in
                                DisclosureGroup(
                                    isExpanded: bindingForDay(dayGroup.dayStart)
                                ) {
                                    dayContent(for: dayGroup.dayStart)
                                } label: {
                                    Text("\(dayGroup.title)  (\(dayCountLabel(for: dayGroup.dayStart)))")
                                        .font(.headline)
                                }
                                .onAppear {
                                    onEnsureDayCount(dayGroup.dayStart)
                                }
                            }
                        } label: {
                            Text(monthGroup.title)
                                .font(.headline)
                        }
                    }
                } label: {
                    Text(yearGroup.title)
                        .font(.headline)
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
                    onDeleteItem: onDeleteItem
                )
            }
        }

        if dayHasMoreProvider(dayStart) {
            Button {
                onLoadMoreDayItems(dayStart)
            } label: {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading...")
                    }
                } else {
                    Text("Load More")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var directSearchResultsList: some View {
        Group {
            if flatSearchItems.isEmpty {
                ContentUnavailableView(
                    "No Matching Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different keyword.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            onDeleteItem: onDeleteItem
                        )
                    }

                    if canLoadMoreSearchResults || isLoadingSearchResults {
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
            }
        }
    }

    private var iPhoneNavigationList: some View {
        List {
            ForEach(yearGroups) { yearGroup in
                NavigationLink {
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
                        onEnsureDayCount: onEnsureDayCount,
                        onEnsureDayItems: onEnsureDayItems,
                        onLoadMoreDayItems: onLoadMoreDayItems
                    )
                } label: {
                    HStack {
                        Text(yearGroup.title)
                            .font(.headline)
                        Spacer()
                        Text(groupCountLabel(for: yearGroup.monthGroups.flatMap(\.dayGroups).map(\.dayStart)))
                            .foregroundStyle(.secondary)
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
    }

    private var isIPhone: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
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

    private func bindingForYear(_ year: Int) -> Binding<Bool> {
        Binding(
            get: { expandedYears.contains(year) },
            set: { isExpanded in
                if isExpanded {
                    expandedYears.insert(year)
                } else {
                    expandedYears.remove(year)
                }
            }
        )
    }

    private func bindingForMonth(_ month: Date) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(month) },
            set: { isExpanded in
                if isExpanded {
                    expandedMonths.insert(month)
                } else {
                    expandedMonths.remove(month)
                }
            }
        )
    }

    private func bindingForDay(_ day: Date) -> Binding<Bool> {
        Binding(
            get: { expandedDays.contains(day) },
            set: { isExpanded in
                if isExpanded {
                    expandedDays.insert(day)
                    onEnsureDayItems(day)
                    onEnsureDayCount(day)
                } else {
                    expandedDays.remove(day)
                }
            }
        )
    }
}

private struct HistoryMonthNavigationList: View {
    let yearGroup: HistoryYearGroup
    let showTime: Bool
    let showSiteIcons: Bool
    let enableDelete: Bool
    let openTapCount: Int
    let dayCountProvider: (Date) -> Int?
    let dayItemsProvider: (Date) -> [Item]
    let dayHasMoreProvider: (Date) -> Bool
    let dayIsLoadingProvider: (Date) -> Bool
    let onOpenItem: (Item) -> Void
    let onDeleteItem: (Item) -> Void
    let onEnsureDayCount: (Date) -> Void
    let onEnsureDayItems: (Date) -> Void
    let onLoadMoreDayItems: (Date) -> Void

    var body: some View {
        List {
            ForEach(yearGroup.monthGroups) { monthGroup in
                NavigationLink {
                    HistoryDayNavigationList(
                        monthGroup: monthGroup,
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
                        onEnsureDayCount: onEnsureDayCount,
                        onEnsureDayItems: onEnsureDayItems,
                        onLoadMoreDayItems: onLoadMoreDayItems
                    )
                } label: {
                    HStack {
                        Text(monthGroup.title)
                            .font(.headline)
                        Spacer()
                        Text(groupCountLabel(for: monthGroup.dayGroups.map(\.dayStart)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(yearGroup.title)
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
}

private struct HistoryDayNavigationList: View {
    let monthGroup: HistoryMonthGroup
    let showTime: Bool
    let showSiteIcons: Bool
    let enableDelete: Bool
    let openTapCount: Int
    let dayCountProvider: (Date) -> Int?
    let dayItemsProvider: (Date) -> [Item]
    let dayHasMoreProvider: (Date) -> Bool
    let dayIsLoadingProvider: (Date) -> Bool
    let onOpenItem: (Item) -> Void
    let onDeleteItem: (Item) -> Void
    let onEnsureDayCount: (Date) -> Void
    let onEnsureDayItems: (Date) -> Void
    let onLoadMoreDayItems: (Date) -> Void

    var body: some View {
        List {
            ForEach(monthGroup.dayGroups) { dayGroup in
                NavigationLink {
                    HistoryRecordList(
                        dayStart: dayGroup.dayStart,
                        dayTitle: dayGroup.title,
                        showTime: showTime,
                        showSiteIcons: showSiteIcons,
                        enableDelete: enableDelete,
                        openTapCount: openTapCount,
                        dayItemsProvider: dayItemsProvider,
                        dayHasMoreProvider: dayHasMoreProvider,
                        dayIsLoadingProvider: dayIsLoadingProvider,
                        onOpenItem: onOpenItem,
                        onDeleteItem: onDeleteItem,
                        onEnsureDayItems: onEnsureDayItems,
                        onLoadMoreDayItems: onLoadMoreDayItems
                    )
                } label: {
                    HStack {
                        Text(dayGroup.title)
                            .font(.headline)
                        Spacer()
                        Text(dayCountProvider(dayGroup.dayStart).map(String.init) ?? "...")
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    onEnsureDayCount(dayGroup.dayStart)
                }
            }
        }
        .navigationTitle(monthGroup.title)
    }
}

private struct HistoryRecordList: View {
    let dayStart: Date
    let dayTitle: String
    let showTime: Bool
    let showSiteIcons: Bool
    let enableDelete: Bool
    let openTapCount: Int
    let dayItemsProvider: (Date) -> [Item]
    let dayHasMoreProvider: (Date) -> Bool
    let dayIsLoadingProvider: (Date) -> Bool
    let onOpenItem: (Item) -> Void
    let onDeleteItem: (Item) -> Void
    let onEnsureDayItems: (Date) -> Void
    let onLoadMoreDayItems: (Date) -> Void

    var body: some View {
        List {
            let items = dayItemsProvider(dayStart)
            let isLoading = dayIsLoadingProvider(dayStart)

            if items.isEmpty {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading records...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No records loaded.")
                        .foregroundStyle(.secondary)
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
                        onDeleteItem: onDeleteItem
                    )
                }
            }

            if dayHasMoreProvider(dayStart) {
                Button {
                    onLoadMoreDayItems(dayStart)
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                        }
                    } else {
                        Text("Load More")
                    }
                }
            }
        }
        .navigationTitle(dayTitle)
        .onAppear {
            onEnsureDayItems(dayStart)
        }
    }
}

private struct HistoryRecordRow: View {
    let item: Item
    let showTime: Bool
    let showSiteIcons: Bool
    let forceShowDate: Bool
    let openTapCount: Int
    let enableDelete: Bool
    let onOpenItem: (Item) -> Void
    let onDeleteItem: (Item) -> Void

    @ViewBuilder
    var body: some View {
        let baseRow = HistoryRowView(
            item: item,
            showTime: showTime,
            showSiteIcons: showSiteIcons,
            forceShowDate: forceShowDate
        )
            .onTapGesture(count: openTapCount) {
                onOpenItem(item)
            }

#if os(iOS)
        if enableDelete {
            baseRow.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDeleteItem(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            baseRow
        }
#else
        baseRow
#endif
    }
}
