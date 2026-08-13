import SwiftUI

struct HistoryLibHelperHelpView: View {
    private let helperDownloadURL = URL(
        string: "https://prods.notion.site/history-lib-helper"
    )!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("HistoryLib Helper", systemImage: "clock.arrow.circlepath")
                        .font(.title2.bold())

                    Text("Bring browser history into HistoryLib.")
                        .font(.headline)

                    Text("HistoryLib Helper is a separate local-only tool for Windows and macOS. It reads supported browser history and exports a .hlz file that HistoryLib can import.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Supported Browsers") {
                Text("Google Chrome, Microsoft Edge, Brave, Vivaldi, Opera, Chromium, and Firefox are supported.")
            }

            Section("Import Options") {
                Text("HistoryLib can directly import only Safari history, Google Takeout exports, and .hlz archives.")

                Text("To import history from a computer or from more browsers, use HistoryLib Helper to create a .hlz archive, then import that archive into HistoryLib.")
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
        .navigationTitle("Help")
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
