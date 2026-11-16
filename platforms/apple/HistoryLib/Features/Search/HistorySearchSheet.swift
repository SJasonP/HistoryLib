import SwiftUI

struct HistorySearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let initialFilter: HistorySearchFilter
    let initialRequest: String
    let onApply: (HistorySearchFilter) -> Void

    @State private var request = ""
    @State private var keywords = ""
    @State private var domain = ""
    @State private var browser = ""
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var startDate = Date()
    @State private var lastDay = Date()
    @State private var isAvailable = false
    @State private var isInterpreting = false
    @State private var interpretation: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var didInitialize = false
    private let interpreter = NaturalLanguageHistorySearch()

    var body: some View {
        NavigationStack {
            Form {
                if HistorySearchFeatureFlags.appleIntelligenceAndSiriEnabled, isAvailable {
                    Section("Describe What You Want to Find") {
                        TextField("Describe your search", text: $request, axis: .vertical)
                            .lineLimit(2...5)
                            .clearableTextInput($request)
                            .disabled(isInterpreting)
                        Text("Only your request is processed on this device. History records are not sent to the model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(action: interpret) {
                            if isInterpreting {
                                Label("Interpreting...", systemImage: "hourglass")
                            } else {
                                Label("Interpret on Device", systemImage: "sparkles")
                            }
                        }
                        .disabled(isInterpreting || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.count > 2_000)
                    }
                }

                Section("Review Search Filters") {
                    TextField("Search terms (one per line)", text: $keywords, axis: .vertical)
                        .lineLimit(1...5)
                        .clearableTextInput($keywords)
                    Text("All terms must match the title or URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Domain (Optional)", text: $domain)
                        .autocorrectionDisabled()
                        .clearableTextInput($domain)
                    Picker("Browser", selection: $browser) {
                        Text("Any Browser").tag("")
                        Text(verbatim: "Safari").tag("Safari")
                        Text(verbatim: "Chrome").tag("Chrome")
                    }
                    Toggle("Start Date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Through", selection: $lastDay, displayedComponents: .date)
                    }
                }
                .disabled(isInterpreting)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("history.search.error")
                    }
                }
            }
            .navigationTitle("Search Filters")
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        interpretation?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search", action: apply)
                        .disabled(isInterpreting)
                }
            }
        }
#if os(macOS)
        .frame(width: 620, height: 430)
#else
        .frame(idealWidth: 520, idealHeight: 650)
#endif
        .interactiveDismissDisabled(isInterpreting)
        .onAppear {
            let available = interpreter.isAvailable
            isAvailable = available
            guard !didInitialize else { return }
            didInitialize = true
            request = initialRequest
            load(initialFilter)
            if HistorySearchFeatureFlags.appleIntelligenceAndSiriEnabled,
               !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               available {
                interpret()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { isAvailable = interpreter.isAvailable }
        }
        .onDisappear { interpretation?.cancel() }
    }

    private func load(_ filter: HistorySearchFilter) {
        keywords = filter.keywords.joined(separator: "\n")
        domain = filter.domain
        browser = filter.browser
        hasStartDate = filter.startDate != nil
        hasEndDate = filter.endDate != nil
        startDate = filter.startDate ?? Date()
        lastDay = filter.endDate.flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) } ?? Date()
    }

    private func interpret() {
        interpretation?.cancel()
        errorMessage = nil
        isInterpreting = true
        interpretation = Task { @MainActor in
            defer { isInterpreting = false }
            do {
                let filter = try await interpreter.interpret(request)
                try Task.checkCancellation()
                load(filter)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? HistorySearchError)?.errorDescription
                    ?? HistorySearchError.interpretationFailed.errorDescription
            }
        }
    }

    private func apply() {
        do {
            let calendar = Calendar.current
            let filter = try HistorySearchFilter(
                keywords: keywords.components(separatedBy: .newlines),
                domain: domain, browser: browser,
                startDate: hasStartDate ? calendar.startOfDay(for: startDate) : nil,
                endDate: hasEndDate ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) : nil
            ).validated()
            onApply(filter)
            dismiss()
        } catch {
            errorMessage = (error as? HistorySearchError)?.errorDescription
        }
    }
}
