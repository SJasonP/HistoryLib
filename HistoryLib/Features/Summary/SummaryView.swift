import SwiftUI

struct SummaryView: View {
    let snapshot: SummarySnapshot?

    var body: some View {
        Group {
            if let snapshot {
                List {
                    LabeledContent("Total Records") {
                        Text("\(snapshot.totalRecords)")
                            .monospacedDigit()
                    }

                    LabeledContent("Average Per Day") {
                        Text(snapshot.averagePerDay, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }

                    LabeledContent("Average Per Month") {
                        Text(snapshot.averagePerMonth, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }

                    LabeledContent("Average Per Year") {
                        Text(snapshot.averagePerYear, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }

                    if !snapshot.topSites.isEmpty {
                        Section("Top 10 Most Visited Sites") {
                            ForEach(Array(snapshot.topSites.enumerated()), id: \.offset) { index, site in
                                HStack {
                                    Text("\(index + 1). \(site.host)")
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(site.visits)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Section("Top 10 Most Visited Sites") {
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
}
