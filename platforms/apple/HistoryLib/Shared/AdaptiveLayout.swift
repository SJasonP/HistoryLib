import SwiftUI

private struct HistorySidebarPlacement: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 27.0, *) {
            content.defaultTabBarPlacement(.sidebar)
        } else {
            content.defaultAdaptableTabBarPlacement(.sidebar)
        }
#else
        content
#endif
    }
}

extension View {
    func historySidebarPlacement() -> some View {
        modifier(HistorySidebarPlacement())
    }
}

/// Keep the cancellation control scrollable in short windows and large text.
/// On foldable displays, the system arrangement also avoids the folding region.
struct TransferProgressOverlay<Panel: View>: View {
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

#if os(iOS)
            if #available(iOS 27.1, *) {
                ArrangementView {
                    scrollablePanel
                } secondary: {
                    Color.clear
                }
                .arrangementViewStyle(.overlay)
            } else {
                scrollablePanel
            }
#else
            scrollablePanel
#endif
        }
        .accessibilityAddTraits(.isModal)
    }

    private var scrollablePanel: some View {
        ScrollView {
            panel()
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
    }
}
