import SwiftUI

/// The sidebar (board `Main`): Library, Sources, Collections, Utilities;
/// counts in secondary on the right, an index status line at the foot.
struct MacSidebar: View {
    @Binding var selection: MacSidebarItem?
    let library: LibraryModel?
    let sources: [SourceStore.Source]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(MacSidebarItem.library) { item in
                    row(item, count: item == .allPhotos ? library?.items.count : nil)
                }
            }
            Section(String(localized: "Sources", comment: "Mac sidebar group")) {
                ForEach(sources, id: \.id) { source in
                    Label(source.name, systemImage: MacSidebar.symbol(forSourceKind: source.kind))
                        .tag(MacSidebarItem.source(source.id))
                }
            }
            Section(String(localized: "Collections", comment: "Mac sidebar group")) {
                ForEach(MacSidebarItem.collections) { row($0, count: nil) }
            }
            Section(String(localized: "Utilities", comment: "Mac sidebar group")) {
                ForEach(MacSidebarItem.utilities) { row($0, count: nil) }
            }
        }
        .safeAreaInset(edge: .bottom) { status }
    }

    private func row(_ item: MacSidebarItem, count: Int?) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer(minLength: 4)
                if let count {
                    Text(count.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }

    @ViewBuilder
    private var status: some View {
        if let library {
            HStack(spacing: 6) {
                Image(systemName: library.isIndexing ? "arrow.triangle.2.circlepath" : "checkmark")
                Text(library.isIndexing
                     ? String(localized: "Indexing…", comment: "Mac sidebar foot: the index is running")
                     : String(localized: "Up to date", comment: "Mac sidebar foot: the index is finished"))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    static func symbol(forSourceKind kind: String) -> String {
        switch kind {
        case "photos": "photo.stack"
        case "drive": "externaldrive"
        case "server": "server.rack"
        default: "folder"
        }
    }
}

/// The sidebar's places (board `Main`).
enum MacSidebarItem: Hashable, Identifiable {
    case allPhotos, favorites, videos, raw, recentlyAdded
    case source(String)
    case onThisDay, albums
    case statistics, duplicates, collages, videoProjects, onServer

    var id: String {
        if case .source(let id) = self { return "source-" + id }
        return title
    }

    static let library: [MacSidebarItem] = [.allPhotos, .favorites, .videos, .raw, .recentlyAdded]
    static let collections: [MacSidebarItem] = [.onThisDay, .albums]
    static let utilities: [MacSidebarItem] = [.statistics, .duplicates, .collages, .videoProjects, .onServer]

    var title: String {
        switch self {
        case .allPhotos: String(localized: "All Photos", comment: "Mac sidebar")
        case .favorites: String(localized: "Favorites", comment: "Mac sidebar")
        case .videos: String(localized: "Videos", comment: "Mac sidebar")
        case .raw: String(localized: "RAW", comment: "Mac sidebar")
        case .recentlyAdded: String(localized: "Recently Added", comment: "Mac sidebar")
        case .source: String(localized: "Source", comment: "Mac sidebar: a photo source")
        case .onThisDay: String(localized: "On This Day", comment: "Mac sidebar")
        case .albums: String(localized: "Albums", comment: "Mac sidebar")
        case .statistics: String(localized: "Statistics", comment: "Mac sidebar")
        case .duplicates: String(localized: "Duplicates", comment: "Mac sidebar")
        case .collages: String(localized: "Collages", comment: "Mac sidebar")
        case .videoProjects: String(localized: "Video Projects", comment: "Mac sidebar")
        case .onServer: String(localized: "On Server", comment: "Mac sidebar")
        }
    }

    var systemImage: String {
        switch self {
        case .allPhotos: "photo.on.rectangle"
        case .favorites: "heart"
        case .videos: "video"
        case .raw: "camera.aperture"
        case .recentlyAdded: "clock"
        case .source: "folder"
        case .onThisDay: "calendar"
        case .albums: "rectangle.stack"
        case .statistics: "chart.bar"
        case .duplicates: "square.on.square"
        case .collages: "square.grid.2x2"
        case .videoProjects: "film"
        case .onServer: "externaldrive.connected.to.line.below"
        }
    }
}
