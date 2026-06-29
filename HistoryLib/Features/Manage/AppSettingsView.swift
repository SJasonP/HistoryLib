import SwiftUI

struct AppSettingsView: View {
    @AppStorage("show_history_time") private var showHistoryTime = true
    @AppStorage("show_site_icons") private var showSiteIcons = true
    @AppStorage("enable_delete") private var enableDelete = false
    @AppStorage("enable_icloud_sync") private var enableICloudSync = false
    @AppStorage("open_record_in_browser_on_click") private var openRecordInBrowserOnDoubleClick = true
    @AppStorage("default_expand_level") private var defaultExpandLevelRaw = HistoryDefaultExpandLevel.day.rawValue

    var body: some View {
        Form {
            Section("Display") {
                SettingsToggleRow(
                    title: "Show Visit Time",
                    description: "Displays HH:mm:ss on each history row.",
                    isOn: $showHistoryTime
                )

                SettingsToggleRow(
                    title: "Show Site Icons",
                    description: "Displays website icons and fetches favicon files.",
                    isOn: $showSiteIcons
                )

                SettingsPickerRow(
                    title: "Default Expand To",
                    description: "Controls how far groups are expanded on launch.",
                    selection: $defaultExpandLevelRaw
                )
            }

            Section("Data") {
                SettingsToggleRow(
                    title: "Enable Deletion",
                    description: "When enabled on iOS, swipe left on a row to reveal Delete.",
                    isOn: $enableDelete
                )

                SettingsToggleRow(
                    title: "Enable iCloud Sync",
                    description: "When off, the app uses local-only storage and skips all iCloud operations.",
                    isOn: $enableICloudSync
                )
            }

            Section("Opening") {
                SettingsToggleRow(
                    title: "Open Link On Tap/Click",
                    description: "Opens the selected URL in your default browser.",
                    isOn: $openRecordInBrowserOnDoubleClick
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 560, minHeight: 360, alignment: .topLeading)
    }
}

private struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct SettingsPickerRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @Binding var selection: String

    var body: some View {
        Picker(selection: $selection) {
            ForEach(HistoryDefaultExpandLevel.allCases) { level in
                Text(level.title).tag(level.rawValue)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    AppSettingsView()
}
