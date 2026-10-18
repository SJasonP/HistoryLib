#if DEBUG
import Foundation
import SwiftData

/// UI regression tests use synthetic records and never open the user's store.
@MainActor
enum UITestStore {
    static func makeContainer(schema: Schema) -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            for index in 0..<12 {
                let date = Date(timeIntervalSince1970: 1_768_478_400 + Double(index * 86_400))
                context.insert(Item(
                    uniqueKey: "adaptive-layout-\(index)",
                    url: "https://example.com/layout/\(index)",
                    title: "Adaptive layout record \(index)",
                    visitedAt: date,
                    visitCount: 1,
                    sourceBrowser: "Safari",
                    sourceFileName: "synthetic-ui-fixture.json",
                    rawTimeUsec: Int64(date.timeIntervalSince1970 * 1_000_000)
                ))
            }
            try context.save()
            return container
        } catch {
            fatalError("Could not create isolated UI test store: \(error)")
        }
    }
}
#endif
