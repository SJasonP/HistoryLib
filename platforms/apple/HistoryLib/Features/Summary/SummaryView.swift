import SwiftUI
import Charts

struct SummaryView: View {
    let snapshot: SummarySnapshot?
    var onSearchHost: (String) -> Void = { _ in }

    var body: some View {
        Group {
            if let snapshot {
                List {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            summaryMetric("Saved Records", value: snapshot.totalRecords.formatted())
                            summaryMetric("Active Days", value: snapshot.activeDays.formatted())
                            summaryMetric("Total Visits", value: snapshot.totalVisits.formatted())
                            summaryMetric("Average Per Active Day", value: snapshot.averagePerActiveDay.formatted(.number.precision(.fractionLength(2))))
                        }
                        .padding(.vertical, 4)
                        Text("Saved records count history entries. Visit totals use each entry's stored visit count, so they can be higher.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Coverage") {
                        LabeledContent("Average Per Month") {
                            Text(snapshot.averagePerMonth, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                        LabeledContent("Average Per Year") {
                            Text(snapshot.averagePerYear, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                        if let oldest = snapshot.oldestVisitedAt, let newest = snapshot.newestVisitedAt {
                            LabeledContent("Date Range") {
                                Text("\(oldest, format: .dateTime.year().month().day()) – \(newest, format: .dateTime.year().month().day())")
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    if !snapshot.monthlyTrend.isEmpty {
                        Section("Activity by Month") {
                            ScrollView(.horizontal) {
                                Chart(snapshot.monthlyTrend) { bucket in
                                    BarMark(
                                        x: .value("Month", bucket.month),
                                        y: .value("Visits", bucket.visits)
                                    )
                                    .foregroundStyle(.tint)
                                }
                                .frame(
                                    width: max(360, CGFloat(snapshot.monthlyTrend.count) * 64),
                                    height: 190
                                )
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel()
                                    }
                                }
                            }
                            .defaultScrollAnchor(.trailing)
                            .scrollIndicators(.hidden)
                        }
                    }

                    if !snapshot.browserBreakdown.isEmpty {
                        Section("Visits by Browser") {
                            ForEach(snapshot.browserBreakdown) { source in
                                HStack {
                                    Text(source.browser)
                                    Spacer()
                                    Text(source.visits.formatted())
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !snapshot.topSites.isEmpty {
                        Section("Top Sites by Visits") {
                            ForEach(Array(snapshot.topSites.enumerated()), id: \.offset) { index, site in
                                Button {
                                    guard site.host != "(unknown)" else { return }
                                    onSearchHost(site.host)
                                } label: {
                                    HStack {
                                        Text("\(index + 1). \(site.host)")
                                            .lineLimit(1)
                                        Spacer()
                                        Text(site.visits.formatted())
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Section("Top Sites by Visits") {
                            Text("No site data.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Last Modified") {
                        Text(snapshot.generatedAt, format: .dateTime.year().month().day().hour().minute().second())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Summary Snapshot",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Import history to generate a summary snapshot.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func summaryMetric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
