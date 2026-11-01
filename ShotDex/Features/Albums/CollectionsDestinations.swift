import SwiftUI

/// Every screen the Collections and Utilities tabs push, registered once and
/// applied to both stacks. The two tabs share pinned tools (a pinned Places
/// opens from Collections) and Shortcut routes, so a destination added to
/// one and forgotten on the other would be a dead link.
struct CollectionsDestinations: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies
    let model: AlbumsModel
    let isLibraryIndexing: Bool

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: AlbumItem.ID.self) { albumId in
                if let album = model.albums.first(where: { $0.id == albumId }) {
                    AlbumDetailScreen(album: album)
                }
            }
            .navigationDestination(for: OnThisDayDestination.self) { destination in
                OnThisDayScreen(initialDate: destination.date ?? .now)
            }
            .navigationDestination(for: SmartAlbumDestination.self) { destination in
                if let item = model.smartQueryAlbums.first(where: { $0.album.id == destination.id }) {
                    SmartAlbumDetailScreen(album: item.album)
                }
            }
            .navigationDestination(for: HiddenPhotosDestination.self) { _ in
                HiddenPhotosScreen()
            }
            .navigationDestination(for: DuplicatesDestination.self) { _ in
                DuplicatesScreen()
            }
            .navigationDestination(for: BackupScreenDestination.self) { _ in
                BackupListScreen()
            }
            .navigationDestination(for: UploadedToServerDestination.self) { _ in
                UploadedToServerScreen()
            }
            .navigationDestination(for: OnServerDestination.self) { _ in
                OnServerScreen()
            }
            .navigationDestination(for: OnCloudDestination.self) { _ in
                OnCloudScreen()
            }
            .navigationDestination(for: ServerShortcutRoute.self) { route in
                if let shortcut = dependencies.serverShortcuts.shortcuts.first(where: { $0.id == route.id }),
                   let server = dependencies.fileServerCatalog.servers.first(where: { $0.id == shortcut.serverId }) {
                    ServerBrowserHost(server: server, start: shortcut.path)
                } else {
                    ContentUnavailableView("Folder Removed", systemImage: "folder")
                }
            }
            .navigationDestination(for: StatisticsDestination.self) { _ in
                StatisticsScreen(isIndexing: isLibraryIndexing)
            }
            .navigationDestination(for: CreationsDestination.self) { destination in
                CreationsScreen(kind: destination.kind)
            }
            .navigationDestination(for: OnThisIPhoneDestination.self) { _ in
                OnThisIPhoneScreen()
            }
    }
}

extension View {
    func collectionsDestinations(model: AlbumsModel, isLibraryIndexing: Bool) -> some View {
        modifier(CollectionsDestinations(model: model, isLibraryIndexing: isLibraryIndexing))
    }
}
