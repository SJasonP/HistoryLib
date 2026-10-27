import SwiftUI

struct HistoryMonthNavigationList: View {
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
                        let count = groupCountLabel(for: monthGroup.dayGroups.map(\.dayStart))
                        Text(count)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                count == "..." ? String(localized: "Record count unavailable") : count
                            )
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
                            .accessibilityLabel(
                                dayCountProvider(dayGroup.dayStart).map(String.init)
                                    ?? String(localized: "Record count unavailable")
                            )
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
                        Label("Loading more records", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Text("Load More")
                    }
                }
                .accessibilityLabel(isLoading ? "Loading more records" : "Load More")
            }
        }
        .navigationTitle(dayTitle)
        .onAppear {
            onEnsureDayItems(dayStart)
        }
    }
}

struct HistoryRecordRow: View {
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
