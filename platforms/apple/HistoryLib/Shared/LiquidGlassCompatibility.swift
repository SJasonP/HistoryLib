import SwiftUI

private struct ExportProgressSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

extension View {
    func exportProgressSurface() -> some View {
        modifier(ExportProgressSurfaceModifier())
    }
}
