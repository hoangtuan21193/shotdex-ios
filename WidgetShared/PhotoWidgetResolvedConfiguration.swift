import Foundation

/// What one placed widget ends up showing, once the menu's answers are laid
/// over the settings the app holds.
///
/// Pure, and the only place the precedence is written down: the Home Screen
/// wins where it said something, and says nothing by default.
struct PhotoWidgetResolvedConfiguration: Equatable {
    var settings: PhotoWidgetSettings
    /// The folder the frames are read from.
    var frameDirectoryName: String
    /// Set when the widget is pointed at an album whose photos the app has not
    /// rendered yet.
    var pendingAlbum: WidgetAlbumCatalog.Album?

    static func resolve(
        kind: PhotoWidgetKind,
        settings: PhotoWidgetSettings,
        albumId: String?,
        albumTitle: String?,
        rotation: PhotoWidgetSettings.Rotation?,
        dimming: Double?,
        frameCount: (String) -> Int
    ) -> PhotoWidgetResolvedConfiguration {
        var settings = settings
        if let rotation { settings.rotation = rotation }
        if let dimming { settings.photoDimming = dimming }

        guard let albumId, !albumId.isEmpty else {
            return PhotoWidgetResolvedConfiguration(
                settings: settings,
                frameDirectoryName: kind.directoryName,
                pendingAlbum: nil
            )
        }

        let title = albumTitle ?? "Album"
        settings.source = .album(collectionId: albumId, title: title)
        let directory = PhotoWidgetSnapshot.albumDirectoryName(albumId: albumId)
        let isReady = frameCount(directory) > 0
        return PhotoWidgetResolvedConfiguration(
            settings: settings,
            frameDirectoryName: directory,
            pendingAlbum: isReady
                ? nil
                : WidgetAlbumCatalog.Album(id: albumId, title: title, count: 0)
        )
    }
}
