import SwiftUI

struct HistoryLibHelperHelpView: View {
    private let helperDownloadURL = URL(
        string: "https://prods.notion.site/history-lib-helper"
    )!

    var body: some View {
        List {
            Section("Help Topics") {
                NavigationLink {
                    helperDetail
                } label: {
                    helpTopicRow(
                        title: "Want more browsers?",
                        subtitle: "Use HistoryLib Helper to import supported desktop browsers.",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                NavigationLink {
                    privacyLockDetail
                } label: {
                    helpTopicRow(
                        title: "Want to lock this app?",
                        subtitle: "Learn how HistoryLib protects access on each platform.",
                        systemImage: "lock.shield"
                    )
                }
            }
        }
        .navigationTitle("Help")
    }

    private var helperDetail: some View {
        List {
            Section {
                Text("HistoryLib Helper is a separate local-only tool for Windows and macOS. It reads supported browser history and exports a .hlz file that HistoryLib can import.")
                    .foregroundStyle(.secondary)
            }

            Section("Supported Browsers") {
                Text("Google Chrome, Microsoft Edge, Brave, Vivaldi, Opera, Chromium, and Firefox are supported.")
            }

            Section("How It Works") {
                helpStep("Download and open HistoryLib Helper on your computer.", number: 1)
                helpStep("Select the history you want to export.", number: 2)
                helpStep("Choose whether to protect the .hlz file with a password, then export it.", number: 3)
                helpStep("Transfer the .hlz file to this device and import it from Manage.", number: 4)
            }

            Section("Privacy") {
                Text("The Helper runs locally, opens browser history databases read-only, and does not upload your history.")
            }

            Section {
                Link(destination: helperDownloadURL) {
                    Label("Download HistoryLib Helper", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            }
        }
        .navigationTitle("Want more browsers?")
    }

    private var privacyLockDetail: some View {
        List {
            Section {
                Text("HistoryLib does not add a second app lock on iOS or iPadOS. Use Apple's system Lock App feature instead.")
                Text("Android uses the device or manufacturer's app lock or Private Space when available. HistoryLib does not add another Android app lock.")
            }

            Section("Desktop") {
                Text("macOS: HistoryLib's privacy lock is enabled by default. Open HistoryLib Settings and turn off Require authentication at launch if you do not want it.")
                Text("Windows: HistoryLib's privacy lock is enabled by default. Open Settings and turn off the authentication option if you do not want it.")
            }

            Section("iOS and iPadOS") {
                helpStep("On the Home Screen, touch and hold HistoryLib.", number: 1)
                helpStep("Choose Require Face ID, Touch ID, or Passcode.", number: 2)
                helpStep("Authenticate to lock or unlock the app. HistoryLib does not provide a second in-app lock.", number: 3)
            }

            Section("Android") {
                helpStep("Open your device's Security or Privacy settings.", number: 1)
                helpStep("Use the device or manufacturer App Lock, or Private Space when available.", number: 2)
                helpStep("Authenticate through the system feature before opening HistoryLib.", number: 3)
            }
        }
        .navigationTitle("Want to lock this app?")
    }

    private func helpTopicRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 6)
    }

    private func helpStep(_ text: LocalizedStringKey, number: Int) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryLibHelperHelpView()
    }
}
