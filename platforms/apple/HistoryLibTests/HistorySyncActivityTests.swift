import Foundation
import Testing
@testable import History_Lib

@MainActor
@Suite("Observed sync activity")
struct HistorySyncActivityTests {
    @Test("Concurrent transfers remain active until all end; setup does not count as synced")
    func transfersAndSetup() {
        let state = HistorySyncActivity()
        let upload = UUID(), download = UUID()
        state.bind(storeIdentifiers: ["fictional-store"])
        state.receive(identifier: UUID(), store: "fictional-store", phase: .setup,
                      endDate: Date(timeIntervalSince1970: 1), succeeded: true, hasError: false)
        #expect(state.lastSuccessfulTransfer == nil)
        #expect(!state.isSyncing)
        for (id, phase) in [(upload, HistorySyncActivity.Phase.upload), (download, .download)] {
            state.receive(identifier: id, store: "fictional-store", phase: phase,
                          endDate: nil, succeeded: false, hasError: false)
        }
        #expect(state.isSyncing)
        let finished = Date(timeIntervalSince1970: 10)
        state.receive(identifier: upload, store: "fictional-store", phase: .upload,
                      endDate: finished, succeeded: true, hasError: false)
        #expect(state.isSyncing)
        #expect(state.lastSuccessfulTransfer == finished)
        state.receive(identifier: download, store: "fictional-store", phase: .download,
                      endDate: finished, succeeded: false, hasError: true)
        #expect(!state.isSyncing)
        #expect(state.hasObservedFailure)
        #expect(state.lastSuccessfulTransfer == finished)
    }

    @Test("Success in one direction cannot conceal a failure in the other")
    func failuresAndEventOrder() {
        let state = HistorySyncActivity()
        state.bind(storeIdentifiers: ["fictional-store"])
        state.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                      endDate: Date(timeIntervalSince1970: 10), succeeded: false, hasError: true)
        state.receive(identifier: UUID(), store: "fictional-store", phase: .download,
                      endDate: Date(timeIntervalSince1970: 20), succeeded: true, hasError: false)
        #expect(state.hasObservedFailure)
        state.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                      endDate: Date(timeIntervalSince1970: 30), succeeded: true, hasError: false)
        #expect(!state.hasObservedFailure)
        state.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                      endDate: Date(timeIntervalSince1970: 5), succeeded: false, hasError: true)
        #expect(!state.hasObservedFailure)
        #expect(state.lastSuccessfulTransfer == Date(timeIntervalSince1970: 30))
    }

    @Test("Startup events are replayed after binding and unrelated stores are ignored")
    func startupAndStoreIdentity() {
        let state = HistorySyncActivity()
        let id = UUID()
        state.receive(identifier: id, store: "fictional-store", phase: .upload,
                      endDate: nil, succeeded: false, hasError: false)
        state.bind(storeIdentifiers: ["fictional-store"])
        #expect(state.isSyncing)
        state.receive(identifier: UUID(), store: "unrelated-store", phase: .download,
                      endDate: Date(timeIntervalSince1970: 100), succeeded: true, hasError: false)
        #expect(state.lastSuccessfulTransfer == nil)
    }

    @Test("Account transitions clear timestamps and reject old-account completions")
    func accountTransition() {
        let state = HistorySyncActivity()
        state.bind(storeIdentifiers: ["fictional-store"])
        state.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                      endDate: Date(timeIntervalSince1970: 20), succeeded: true, hasError: false)
        state.resetAccountSession()
        #expect(state.lastSuccessfulTransfer == nil)
        state.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                      startDate: .distantPast, endDate: Date(), succeeded: true, hasError: false)
        #expect(state.lastSuccessfulTransfer == nil)
        let now = Date()
        state.receive(identifier: UUID(), store: "fictional-store", phase: .download,
                      startDate: now, endDate: now, succeeded: true, hasError: false)
        #expect(state.lastSuccessfulTransfer == now)
    }
}
