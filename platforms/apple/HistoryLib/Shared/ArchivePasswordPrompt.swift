import SwiftUI

struct ArchivePasswordPrompt: View {
    @Binding var password: String
    let errorMessage: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .clearableTextInput($password)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Encrypted Archive")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: onSubmit)
                        .disabled(HistoryLibEncryptedArchive.normalizedPassword(password).isEmpty)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 180)
#endif
    }
}
