import SwiftUI

struct ManageView: View {
    @AppStorage("show_site_icons") private var showSiteIcons = true

    let isSyncing: Bool
    let isPreparingExport: Bool
    let enableDelete: Bool
    let isICloudSyncEnabled: Bool
    let canMutateHistoryData: Bool
    let oldestRecordDate: Date?
    let newestRecordDate: Date?
    let onImportAutoDetect: () -> Void
    let onImportAsSafari: () -> Void
    let onImportAsHistoryLib: () -> Void
    let onRetryICloudSync: () -> Void
    let onExport: (HistoryExportFormat, HistoryExportSplit) -> Void
    let onClearCache: () -> Void
    let onBatchDelete: (ClosedRange<Date>) -> Int
    let onCountRecordsInRange: (ClosedRange<Date>) -> Int

    @State private var selectedExportFormat: HistoryExportFormat = .historyLib
    @State private var selectedExportSplit: HistoryExportSplit = .single
    @State private var isShowingBatchDeleteSheet = false
    @State private var isShowingClearCacheAlert = false
    @State private var shouldDisableIconsAfterClear = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isShowingDeleteConfirmation = false
    @State private var confirmedDeleteRange: ClosedRange<Date>?
    @State private var confirmedDeleteCount = 0

    var body: some View {
        List {
            if !canMutateHistoryData {
                Section {
                    Label("CloudKit is unavailable. History changes are currently blocked.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Import") {
                Button {
                    onImportAutoDetect()
                } label: {
                    Label("Import (Auto Detect)", systemImage: "wand.and.stars")
                }
                .disabled(!canMutateHistoryData)

                Button {
                    onImportAsSafari()
                } label: {
                    Label("Import as Safari Export", systemImage: "safari")
                }
                .disabled(!canMutateHistoryData)

                Button {
                    onImportAsHistoryLib()
                } label: {
                    Label("Import as HistoryLib Archive", systemImage: "archivebox")
                }
                .disabled(!canMutateHistoryData)
            }

            Section("Export") {
                Picker("Format", selection: $selectedExportFormat) {
                    ForEach(HistoryExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.menu)

                if selectedExportFormat == .safari {
                    Picker("Layout", selection: $selectedExportSplit) {
                        ForEach(HistoryExportSplit.allCases) { split in
                            Text(split.title).tag(split)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("HistoryLib export always uses one optimized .hlz archive format.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onExport(selectedExportFormat, selectedExportSplit)
                } label: {
                    if isPreparingExport {
                        Label("Preparing Export...", systemImage: "hourglass")
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingExport)
            }

            Section("Data") {
                Button("Check iCloud Sync", action: onRetryICloudSync)
                    .disabled(isSyncing || !isICloudSyncEnabled)

                Button("Clear Cache") {
                    shouldDisableIconsAfterClear = showSiteIcons
                    isShowingClearCacheAlert = true
                }

                if enableDelete && canMutateHistoryData {
                    Button(role: .destructive) {
                        prepareBatchDeleteDefaults()
                        isShowingBatchDeleteSheet = true
                    } label: {
                        Text("Batch Delete")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingBatchDeleteSheet) {
            batchDeleteSheet
        }
        .alert(clearCacheTitle, isPresented: $isShowingClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Cache", role: .destructive) {
                if shouldDisableIconsAfterClear {
                    showSiteIcons = false
                }
                onClearCache()
            }
        } message: {
            Text(clearCacheMessage)
        }
    }

    private var batchDeleteSheet: some View {
        NavigationStack {
            Form {
                Section("Delete Time Range") {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
#if os(iOS)
                    .datePickerStyle(.compact)
#endif

                    DatePicker(
                        "End",
                        selection: $endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
#if os(iOS)
                    .datePickerStyle(.compact)
#endif
                }
            }
            .navigationTitle("Batch Delete")
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue {
                    endDate = newValue
                }
            }
            .onChange(of: endDate) { _, newValue in
                if newValue < startDate {
                    startDate = newValue
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingBatchDeleteSheet = false
                    }
                }

                ToolbarItem(placement: .destructiveAction) {
                    Button(deleteButtonTitle, role: .destructive) {
                        guard let validRange else { return }
                        confirmedDeleteRange = validRange
                        confirmedDeleteCount = matchingDeleteCount
                        isShowingDeleteConfirmation = true
                    }
                    .disabled(validRange == nil)
                }
            }
            .alert("Confirm Batch Delete", isPresented: $isShowingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(confirmedDeleteCount) Records", role: .destructive) {
                    guard let confirmedDeleteRange else { return }
                    _ = onBatchDelete(confirmedDeleteRange)
                    isShowingBatchDeleteSheet = false
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private var deleteButtonTitle: String {
        "Delete \(matchingDeleteCount) Records"
    }

    private var matchingDeleteCount: Int {
        guard let range = validRange else { return 0 }
        return onCountRecordsInRange(range)
    }

    private var validRange: ClosedRange<Date>? {
        guard startDate <= endDate else {
            return nil
        }
        return startDate...endDate
    }

    private func prepareBatchDeleteDefaults() {
        if let oldestRecordDate, let newestRecordDate {
            startDate = oldestRecordDate
            endDate = newestRecordDate
        } else {
            let now = Date()
            startDate = now
            endDate = now
        }
        confirmedDeleteRange = nil
        confirmedDeleteCount = 0
        isShowingDeleteConfirmation = false
    }

    private var clearCacheTitle: String {
        "Clear Cache"
    }

    private var clearCacheMessage: String {
        if shouldDisableIconsAfterClear {
            return "Continuing will also turn off Show Site Icons. Do you want to continue?"
        }
        return "This will clear favicon cache files. Do you want to continue?"
    }
}
