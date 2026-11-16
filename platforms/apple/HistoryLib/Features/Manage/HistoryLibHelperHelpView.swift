import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct HistoryLibHelperHelpView: View {
    private let helperDownloadURL = URL(
        string: "https://prods.notion.site/history-lib-helper"
    )!
    private let issuesURL = URL(
        string: "https://github.com/SJasonP/HistoryLib"
    )!
    private let developerEmail = "SJasonP@iCloud.com"

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

                NavigationLink {
                    feedbackDetail
                } label: {
                    helpTopicRow(
                        title: "Have a problem or suggestion?",
                        subtitle: "Tell us what happened or what you would like to see next.",
                        systemImage: "bubble.left.and.bubble.right"
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
            Section("iOS and iPadOS") {
                helpStep("On the Home Screen, touch and hold HistoryLib.", number: 1)
                helpStep("Choose Require Face ID, Touch ID, or Passcode.", number: 2)
                helpStep("Authenticate to lock or unlock the app. HistoryLib does not provide a second in-app lock.", number: 3)
            }

            Section("macOS") {
                Text("HistoryLib's privacy lock is enabled by default. Open HistoryLib Settings and turn off Require authentication at launch if you do not want it.")
            }
        }
        .navigationTitle("Want to lock this app?")
    }

    private var feedbackDetail: some View {
        List {
            Section {
                Text("GitHub Issues is the best place for bug reports and suggestions. It keeps the conversation visible, makes it easier to follow updates, and helps avoid duplicate reports.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Public feedback (recommended)")
            }

            Section {
                Link(destination: issuesURL) {
                    Label("Open GitHub Issues", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            }

            Section {
                Text("If you prefer to share something privately, you can email the developer instead.")
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "mailto:\(developerEmail)")!) {
                    Label("Email the Developer", systemImage: "envelope")
                }

                Text(developerEmail)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy Email Address") {
                            copyEmailAddress()
                        }
                    }
            } header: {
                Text("Private feedback")
            }

        }
        .navigationTitle("Feedback")
    }

    private func copyEmailAddress() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(developerEmail, forType: .string)
#else
        UIPasteboard.general.string = developerEmail
#endif
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
