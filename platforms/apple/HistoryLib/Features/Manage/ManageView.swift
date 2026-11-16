import SwiftUI
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ManageView: View {
    @AppStorage("show_site_icons") var showSiteIcons = true
    @Environment(\.scenePhase) var scenePhase
    @State var diagnostics = ManageDiagnostics()
    let syncActivity = HistorySyncActivity.shared
    @State var isVisible = false
    @State private var accountGeneration = 0
    @State var showingICloudGuide = false
    @State var showingClearCacheConfirmation = false
    @State var showingCacheResult = false
    @State var cacheResultMessage = ""

    let isPreparingExport: Bool
    let enableDelete: Bool
    let isActive: Bool
    let isImporting: Bool
    let storageModeMessage: String
    let canMutateHistoryData: Bool
    let oldestRecordDate: Date?
    let newestRecordDate: Date?
    let onImport: () -> Void
    let onCountLocalRecords: () throws -> Int
    let onExport: (HistoryExportFormat, HistoryExportSplit, String?) -> Void
    let onMeasureStorageUsage: () async -> ClearCacheStorageUsage
    let onClearCache: () async -> DatabaseJournalMaintenance.Outcome
    let onBatchDelete: (ClosedRange<Date>) -> Int
    let onCountRecordsInRange: (ClosedRange<Date>) -> Int

    @State private var selectedExportFormat: HistoryExportFormat = .historyLib
    @State private var selectedExportSplit: HistoryExportSplit = .single
    @State private var isShowingBatchDeleteSheet = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isShowingDeleteConfirmation = false
    @State private var confirmedDeleteRange: ClosedRange<Date>?
    @State private var confirmedDeleteCount = 0
    @State private var matchingDeleteCount = 0
    @State private var exportPassword = ""
    @State private var exportPasswordConfirmation = ""
    @State private var isShowingWeakPasswordAlert = false

    var body: some View {
        List {
            if !canMutateHistoryData {
                Section {
                    Label(storageModeMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Import") {
                Button {
                    onImport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .foregroundStyle(importButtonColor)
                .disabled(!canMutateHistoryData || diagnostics.isClearing)
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
                } else if selectedExportFormat == .historyLib {
                    passwordField("Password (Optional)", text: $exportPassword)

                    if !normalizedExportPassword.isEmpty {
                        passwordField("Confirm Password", text: $exportPasswordConfirmation)

                        if !passwordsMatch {
                            Text("Passwords do not match.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button {
                    prepareExport()
                } label: {
                    if isPreparingExport {
                        Label("Preparing Export...", systemImage: "hourglass")
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingExport || !passwordsMatch || diagnostics.isClearing)
            }

            syncSection
            cacheSection

            if enableDelete && canMutateHistoryData {
                Section("Data") {
                    Button(role: .destructive) {
                        prepareBatchDeleteDefaults()
                        isShowingBatchDeleteSheet = true
                    } label: {
                        Text("Batch Delete")
                    }
                    .disabled(diagnostics.isClearing)
                }
            }

            Section {
                NavigationLink {
                    HistoryLibHelperHelpView()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }

                NavigationLink {
                    TipSupportView()
                } label: {
                    Label("Support Us", systemImage: "heart.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingBatchDeleteSheet) {
            batchDeleteSheet
        }
        .alert("Change iCloud Settings", isPresented: $showingICloudGuide) {
            Button("OK", action: openSystemSettings)
        } message: {
            Text(iCloudSettingsGuide)
        }
        .alert("Clear Cache", isPresented: $showingClearCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Cache", role: .destructive, action: beginClearCache)
        } message: {
            Text(clearCacheConfirmationMessage)
        }
        .alert("Clear Cache Result", isPresented: $showingCacheResult) {
            Button("OK") { }
        } message: {
            Text(cacheResultMessage)
        }
        .alert("Weak Password", isPresented: $isShowingWeakPasswordAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Export Anyway", action: performExport)
        } message: {
            Text("This password is shorter than 12 characters and may be easier to guess.")
        }
        .onChange(of: selectedExportFormat) { _, format in
            if format != .historyLib {
                clearExportPassword()
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; clearExportPassword() }
        .task(id: monitoringEnabled) {
            guard monitoringEnabled else { return }
            await diagnostics.monitorLocal(count: onCountLocalRecords, measure: onMeasureStorageUsage)
        }
        .task(id: "\(monitoringEnabled)-\(accountGeneration)") {
            guard monitoringEnabled else { return }
            await diagnostics.monitorCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            accountGeneration += 1
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
            .task(id: deleteRangeKey) {
                // Debounce rapid date-picker changes, then recompute once.
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                recomputeMatchingDeleteCount()
            }
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

    // Accent when actionable; a dimmed gray when disabled so the buttons clearly
    // read as non-tappable instead of just losing their tint.
    private var importButtonColor: Color {
        canMutateHistoryData ? Color.accentColor : Color.secondary
    }

    private var normalizedExportPassword: String {
        HistoryLibEncryptedArchive.normalizedPassword(exportPassword)
    }

    private var passwordsMatch: Bool {
        guard selectedExportFormat == .historyLib, !normalizedExportPassword.isEmpty else {
            return true
        }
        return normalizedExportPassword
            == HistoryLibEncryptedArchive.normalizedPassword(exportPasswordConfirmation)
    }

    private func passwordField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textContentType(.newPassword)
            .clearableTextInput(text)
    }

    private func prepareExport() {
        guard passwordsMatch else { return }
        if selectedExportFormat == .historyLib,
           !normalizedExportPassword.isEmpty,
           normalizedExportPassword.count < HistoryLibEncryptedArchive.weakPasswordLength {
            isShowingWeakPasswordAlert = true
            return
        }
        performExport()
    }

    private func performExport() {
        let password = selectedExportFormat == .historyLib && !normalizedExportPassword.isEmpty
            ? normalizedExportPassword
            : nil
        clearExportPassword()
        onExport(selectedExportFormat, selectedExportSplit, password)
    }

    private func clearExportPassword() {
        exportPassword = ""
        exportPasswordConfirmation = ""
    }

    private var deleteButtonTitle: String {
        String(localized: "Delete \(matchingDeleteCount) Records")
    }

    // Keyed identity for the current range so the count is recomputed only when
    // the range actually changes, never on every view-body evaluation.
    private var deleteRangeKey: String {
        "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)"
    }

    private func recomputeMatchingDeleteCount() {
        matchingDeleteCount = validRange.map(onCountRecordsInRange) ?? 0
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
        matchingDeleteCount = 0
        isShowingDeleteConfirmation = false
    }

}
