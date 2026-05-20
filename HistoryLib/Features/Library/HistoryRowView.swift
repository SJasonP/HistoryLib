import SwiftUI

#if os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#else
import UIKit
private typealias PlatformImage = UIImage
#endif

struct HistoryRowView: View {
    static let siteIconSize: CGFloat = 16

    let item: Item
    let showTime: Bool
    let showSiteIcons: Bool
    let forceShowDate: Bool

    init(item: Item, showTime: Bool, showSiteIcons: Bool, forceShowDate: Bool = false) {
        self.item = item
        self.showTime = showTime
        self.showSiteIcons = showSiteIcons
        self.forceShowDate = forceShowDate
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if showSiteIcons {
                FaviconView(urlString: item.url)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if forceShowDate {
                        Text(Self.shortDateFormatter.string(from: item.visitedAt))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if showTime {
                        Text(
                            item.visitedAt,
                            format: Date.FormatStyle()
                                .hour(.twoDigits(amPM: .omitted))
                                .minute(.twoDigits)
                                .second(.twoDigits)
                        )
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }

                    Text(item.title.isEmpty ? displayHostOrURL(item.url) : item.title)
                        .lineLimit(1)
                }

                Text(item.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func displayHostOrURL(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL), let host = url.host, !host.isEmpty else {
            return rawURL
        }
        return host
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yy-MM-dd"
        return formatter
    }()
}

private struct FaviconView: View {
    let urlString: String
    @State private var platformImage: PlatformImage?

    var body: some View {
        ZStack {
            if let platformImage {
                iconView(platformImage)
            }
        }
        .frame(width: HistoryRowView.siteIconSize, height: HistoryRowView.siteIconSize)
        .task(id: urlString) {
            await loadFavicon()
        }
    }

    @MainActor
    private func loadFavicon() async {
        platformImage = nil

        guard let data = await FaviconStore.shared.faviconData(for: urlString),
              let image = PlatformImage(data: data) else {
            return
        }
        platformImage = image
    }

    @ViewBuilder
    private func iconView(_ image: PlatformImage) -> some View {
#if os(macOS)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: HistoryRowView.siteIconSize, height: HistoryRowView.siteIconSize)
            .clipShape(RoundedRectangle(cornerRadius: 3))
#else
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: HistoryRowView.siteIconSize, height: HistoryRowView.siteIconSize)
            .clipShape(RoundedRectangle(cornerRadius: 3))
#endif
    }
}
