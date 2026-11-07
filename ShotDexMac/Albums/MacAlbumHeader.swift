import SwiftUI

/// The head of an album opened from Albums (board `MAC_AlbumDetail`): its
/// cover, its name, when and where, and what it holds — over the album's
/// grid in place of the toolbar's title.
struct MacAlbumHeader: View {
    let title: String
    let summary: MacAlbumHeaderSummary
    /// "2 selected", or nil.
    let selected: Int
    /// The album's own size while a search narrows the rows: "3 of 412 photos".
    var total: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MacAssetCover(assetId: summary.cover, side: 208)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                .accessibilityLabel(String(localized: "Album cover", comment: "Mac album: the header's cover"))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold)).frame(minHeight: 26).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let line = summary.whenAndWhere {
                    Text(line).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(countLine).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        // On the grid's own edges (board): cover, text and divider at its inset.
        .padding(.top, 12)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Divider() }
        .padding(.horizontal, MacGridMetrics.sideInset)
    }

    /// "412 photos · 18 videos · 61.4 GB · 2 selected".
    private var countLine: String {
        var parts = [LibraryCountLine.text(shown: summary.photos + summary.videos, videos: summary.videos, total: total, isFiltered: total != nil)]
        if summary.bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file)) }
        if selected > 0 { parts.append(String(localized: "\(selected) selected", comment: "Mac toolbar subtitle: photos selected (plural)")) }
        return parts.joined(separator: " · ")
    }
}

/// What the header says, worked out off the main actor from the grid's rows.
struct MacAlbumHeaderSummary: Equatable, Sendable {
    var cover: String?
    var photos = 0
    var videos = 0
    var bytes: Int64 = 0
    /// "August 9 – 22, 2026 · Reykjavík, Vík, Höfn, Akureyri".
    var whenAndWhere: String?

    static func make(_ items: [LibraryGridItem], places: [String]) -> MacAlbumHeaderSummary {
        var summary = MacAlbumHeaderSummary()
        var first: Date?, last: Date?
        for item in items {
            if MediaKind(storedValue: item.mediaType) == .video { summary.videos += 1 } else { summary.photos += 1 }
            summary.bytes += Int64(item.fileSize ?? 0)
            if let date = item.creationDateValue {
                if first.map({ date < $0 }) ?? true { first = date }
                // The newest photo is the cover, as in Albums.
                if last.map({ date > $0 }) ?? true { last = date; summary.cover = item.assetId }
            }
        }
        if summary.cover == nil { summary.cover = items.last?.assetId }
        var parts: [String] = []
        if let first, let last { parts.append((first..<max(last, first.addingTimeInterval(1))).formatted(.interval.month(.wide).day().year())) }
        if !places.isEmpty { parts.append(places.joined(separator: ", ")) }
        summary.whenAndWhere = parts.isEmpty ? nil : parts.joined(separator: " · ")
        return summary
    }
}
