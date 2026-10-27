#if os(macOS)
import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class MacPrivacyLock {
    static let shared = MacPrivacyLock()

    private static let settingKey = "privacy_lock_enabled"

    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var authenticationFailed = false

    var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.settingKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.settingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.settingKey)
            if !newValue {
                isUnlocked = true
                authenticationFailed = false
            } else if !isAuthenticating {
                isUnlocked = false
            }
        }
    }

    func authenticateIfNeeded() async {
        guard !isUnlocked else { return }
        guard isEnabled else {
            isUnlocked = true
            return
        }
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authenticationFailed = false
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Authenticate to open HistoryLib")
            )
            guard authenticated else {
                authenticationFailed = true
                return
            }
            isUnlocked = true
        } catch {
            authenticationFailed = true
        }
    }
}

struct MacPrivacyLockGate<Content: View>: View {
    @State private var lock = MacPrivacyLock.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if lock.isUnlocked {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)
                    Text("Unlock HistoryLib")
                        .font(.title2.bold())
                    Text("Use Touch ID, Apple Watch, or your Mac password to continue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360)
                    if lock.authenticationFailed {
                        Text("Authentication failed. Try again.")
                            .foregroundStyle(.red)
                    }
                    Button("Retry authentication") {
                        Task { await lock.authenticateIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lock.isAuthenticating)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await lock.authenticateIfNeeded() }
            }
        }
    }
}
#endif
