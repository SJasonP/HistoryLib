import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

/// Passive event capture; never starts a sync or polls while Manage is hidden.
@MainActor
@Observable
final class HistorySyncActivity {
    enum Phase: Hashable { case setup, upload, download }
    private struct EventSnapshot {
        let identifier: UUID
        let store: String
        let phase: Phase
        let startDate: Date
        let endDate: Date?
        let succeeded: Bool
        let hasError: Bool
    }

    static let shared = HistorySyncActivity()

    private(set) var lastSuccessfulTransfer: Date?
    private(set) var isBound = false
    private var activeTransfers: Set<UUID> = []
    private var failedPhases: Set<Phase> = []
    private var completionDates: [Phase: Date] = [:]
    private var pendingEvents: [EventSnapshot] = []
    private var didBind = false
    private var acceptEventsAfter = Date.distantPast
    private var storeIdentifiers: Set<String> = []
    private var boundContainer: ModelContainer?
    private var observers: [NSObjectProtocol] = []

    var isSyncing: Bool { !activeTransfers.isEmpty }
    var hasObservedFailure: Bool { !failedPhases.isEmpty }

    func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.receive(event) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetAccountSession() }
        })
    }

    func bind(to container: ModelContainer) {
        boundContainer = container
        let identifiers = container.configurations.compactMap { configuration -> String? in
            if #available(iOS 27, macOS 27, *),
               let identifier = container.storeIdentifier(forConfigurationNamed: configuration.name) {
                return identifier
            }
            let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: configuration.url,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            return metadata?[NSStoreUUIDKey] as? String
        }
        bind(storeIdentifiers: Set(identifiers))
    }

    // Also permits fictional store identities in state-transition tests.
    func bind(storeIdentifiers: Set<String>) {
        self.storeIdentifiers = storeIdentifiers
        isBound = !storeIdentifiers.isEmpty
        didBind = true
        clearState()
        let pending = pendingEvents
        pendingEvents.removeAll()
        for event in pending { apply(event) }
    }

    func resetAccountSession() {
        acceptEventsAfter = Date()
        pendingEvents.removeAll()
        clearState()
    }

    private func clearState() {
        activeTransfers.removeAll()
        lastSuccessfulTransfer = nil
        failedPhases.removeAll()
        completionDates.removeAll()
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        let phase: Phase
        switch event.type {
        case .setup: phase = .setup
        case .import: phase = .download
        case .export: phase = .upload
        @unknown default: return
        }
        receive(identifier: event.identifier, store: event.storeIdentifier,
                phase: phase, startDate: event.startDate, endDate: event.endDate,
                succeeded: event.succeeded, hasError: event.error != nil)
    }

    func receive(identifier: UUID, store: String, phase: Phase, startDate: Date = .distantPast,
                 endDate: Date?, succeeded: Bool, hasError: Bool) {
        let event = EventSnapshot(identifier: identifier, store: store, phase: phase,
                                  startDate: startDate, endDate: endDate, succeeded: succeeded, hasError: hasError)
        if !didBind {
            if pendingEvents.count == 128 { pendingEvents.removeFirst() }
            pendingEvents.append(event)
            return
        }
        apply(event)
    }

    private func apply(_ event: EventSnapshot) {
        guard event.startDate >= acceptEventsAfter, belongsToStore(event.store) else { return }
        guard let endDate = event.endDate else {
            if event.phase != .setup { activeTransfers.insert(event.identifier) }
            return
        }
        activeTransfers.remove(event.identifier)
        guard endDate >= (completionDates[event.phase] ?? .distantPast) else { return }
        completionDates[event.phase] = endDate
        if !event.succeeded || event.hasError {
            failedPhases.insert(event.phase)
        } else {
            failedPhases.remove(event.phase)
            guard event.phase != .setup else { return }
            // A setup or a cloud-count request is not a successful transfer.
            lastSuccessfulTransfer = max(lastSuccessfulTransfer ?? .distantPast, endDate)
        }
    }

    private func belongsToStore(_ identifier: String) -> Bool {
        if storeIdentifiers.contains(identifier) { return true }
        guard let container = boundContainer else { return false }
        let matches: Bool
        if #available(iOS 27, macOS 27, *) {
            matches = container.configurationName(forStoreIdentifier: identifier) != nil
        } else {
            matches = container.configurations.contains { configuration in
                let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                    ofType: NSSQLiteStoreType, at: configuration.url,
                    options: [NSReadOnlyPersistentStoreOption: true]
                )
                return metadata?[NSStoreUUIDKey] as? String == identifier
            }
        }
        if matches { storeIdentifiers.insert(identifier); isBound = true }
        return matches
    }
}
