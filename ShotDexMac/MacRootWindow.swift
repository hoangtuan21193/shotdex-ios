import SwiftUI

/// The Library window (board `Main`): sources, collections and utilities in
/// the sidebar; the selected place in the content.
struct MacRootWindow: View {
    @State private var selection: MacSidebarItem? = .allPhotos

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(MacSidebarItem.library) { row($0) }
                }
                Section(String(localized: "Sources", comment: "Mac sidebar group")) {
                    row(.photosLibrary)
                }
                Section(String(localized: "Collections", comment: "Mac sidebar group")) {
                    ForEach(MacSidebarItem.collections) { row($0) }
                }
                Section(String(localized: "Utilities", comment: "Mac sidebar group")) {
                    ForEach(MacSidebarItem.utilities) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(MacWindowMetrics.sidebarWidth)
        } detail: {
            Text(selection?.title ?? "")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection?.title ?? "ShotDex")
        }
        .tint(MacTheme.accent)
    }

    private func row(_ item: MacSidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage).tag(item)
    }
}

/// The sidebar's places (board `Main`).
enum MacSidebarItem: String, Hashable, Identifiable {
    case allPhotos, favorites, videos, raw, recentlyAdded
    case photosLibrary
    case onThisDay, albums
    case places, trips, statistics, duplicates, collages, videoProjects, onServer

    var id: String { rawValue }

    static let library: [MacSidebarItem] = [.allPhotos, .favorites, .videos, .raw, .recentlyAdded]
    static let collections: [MacSidebarItem] = [.onThisDay, .albums]
    static let utilities: [MacSidebarItem] = [.places, .trips, .statistics, .duplicates, .collages, .videoProjects, .onServer]

    var title: String {
        switch self {
        case .allPhotos: String(localized: "All Photos", comment: "Mac sidebar")
        case .favorites: String(localized: "Favorites", comment: "Mac sidebar")
        case .videos: String(localized: "Videos", comment: "Mac sidebar")
        case .raw: String(localized: "RAW", comment: "Mac sidebar")
        case .recentlyAdded: String(localized: "Recently Added", comment: "Mac sidebar")
        case .photosLibrary: String(localized: "Photos Library", comment: "Mac sidebar source")
        case .onThisDay: String(localized: "On This Day", comment: "Mac sidebar")
        case .albums: String(localized: "Albums", comment: "Mac sidebar")
        case .places: String(localized: "Places", comment: "Mac sidebar")
        case .trips: String(localized: "Trips", comment: "Mac sidebar")
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
        case .photosLibrary: "photo.stack"
        case .onThisDay: "calendar"
        case .albums: "rectangle.stack"
        case .places: "map"
        case .trips: "mappin.and.ellipse"
        case .statistics: "chart.bar"
        case .duplicates: "square.on.square"
        case .collages: "square.grid.2x2"
        case .videoProjects: "film"
        case .onServer: "externaldrive.connected.to.line.below"
        }
    }
}
