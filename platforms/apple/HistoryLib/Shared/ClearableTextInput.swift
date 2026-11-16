import SwiftUI

private struct ClearableTextInputModifier: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        HStack(spacing: 4) {
            content
                .layoutPriority(1)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Text")
                .help("Clear Text")
            }
        }
    }
}

extension View {
    func clearableTextInput(_ text: Binding<String>) -> some View {
        modifier(ClearableTextInputModifier(text: text))
    }
}
