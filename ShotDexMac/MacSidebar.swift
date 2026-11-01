import SwiftUI

/// The sidebar (board `Main`): Library, Sources, Collections, Utilities;
/// counts in secondary on the right, an index status line at the foot.
struct MacSidebar: View {
    @Binding var selection: MacSidebarItem?
    let library: LibraryModel?
    let sources: [SourceStore.Source]
    /// The Backup row's count, or a warning dot when a job needs the user
    /// (FS-22.06 §5.1).
    var backup: (jobs: Int, needsAttention: Bool) = (0, false)
    var smartAlbums: [SmartAlbum] = []
    var newSmartAlbum: () -> Void = {}

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
            Section {
                ForEach(MacSidebarItem.collections) { row($0, count: nil) }
                ForEach(smartAlbums) { album in
                    Label(album.name, systemImage: MacSidebarItem.smartAlbum(album.id).systemImage)
                        .tag(MacSidebarItem.smartAlbum(album.id))
                }
            } header: {
                HStack {
                    Text("Collections", comment: "Mac sidebar group")
                    Spacer()
                    Button(action: newSmartAlbum) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "New Smart Album… (⌥⌘N)", comment: "Mac sidebar: add a smart album"))
                        .accessibilityLabel(String(localized: "New Smart Album", comment: "Mac sidebar: add a smart album"))
                }
            }
            Section(String(localized: "Utilities", comment: "Mac sidebar group")) {
                ForEach(MacSidebarItem.utilities) { item in
                    if item == .backup {
                        backupRow
                    } else {
                        row(item, count: nil)
                    }
                }
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

    private var backupRow: some View {
        Label {
            HStack {
                Text(MacSidebarItem.backup.title)
                Spacer(minLength: 4)
                if backup.needsAttention {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .accessibilityLabel(String(localized: "Needs attention", comment: "Mac sidebar: a backup job has a problem"))
                } else if backup.jobs > 0 {
                    Text(backup.jobs.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: MacSidebarItem.backup.systemImage)
        }
        .tag(MacSidebarItem.backup)
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
    case smartAlbum(String)
    case backup, statistics, duplicates, collages, videoProjects, onServer

    var id: String {
        if case .source(let id) = self { return "source-" + id }
        if case .smartAlbum(let id) = self { return "smart-" + id }
        return title
    }

    static let library: [MacSidebarItem] = [.allPhotos, .favorites, .videos, .raw, .recentlyAdded]
    static let collections: [MacSidebarItem] = [.onThisDay, .albums]
    static let utilities: [MacSidebarItem] = [.backup, .statistics, .duplicates, .collages, .videoProjects, .onServer]

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
        case .smartAlbum: String(localized: "Smart Album", comment: "Mac sidebar: a smart album")
        case .backup: String(localized: "Backup", comment: "Mac sidebar")
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
        case .smartAlbum: "gearshape.2"
        case .backup: "clock.arrow.circlepath"
        case .statistics: "chart.bar"
        case .duplicates: "square.on.square"
        case .collages: "square.grid.2x2"
        case .videoProjects: "film"
        case .onServer: "externaldrive.connected.to.line.below"
        }
    }
}
