import Foundation

/// Where one widget reads its pictures from, once the settings say what its
/// source is.
///
/// The settings are the single answer to "what is this widget showing" — the
/// app writes them from its own screen, the widget writes them when the Home
/// Screen's menu says something new — so this no longer merges two opinions.
/// What is left is a lookup: which folder holds that source's frames, and
/// whether they exist yet.
struct PhotoWidgetResolvedConfiguration: Equatable {
    /// The folder the frames are read from.
    var frameDirectoryName: String
    /// Set when the source has no frames rendered yet, which is what makes the
    /// widget ask the app for them and say so on screen.
    var pendingSource: PendingSource?

    struct PendingSource: Equatable {
        enum Kind: Equatable {
            case album
            case photo
        }

        var id: String
        var title: String
        var kind: Kind
    }

    /// `snapshot` is passed in rather than read here so this stays pure and
    /// testable; the widget hands it a cached read.
    static func resolve(
        designId: String,
        source: PhotoWidgetSettings.Source,
        snapshot: (String) -> PhotoWidgetSnapshot
    ) -> PhotoWidgetResolvedConfiguration {
        switch source {
        case .none:
            return PhotoWidgetResolvedConfiguration(
                frameDirectoryName: PhotoWidgetDesign.directoryName(id: designId),
                pendingSource: nil
            )

        case .photo(let assetId):
            return resolve(
                designId: designId,
                sourceId: assetId,
                title: "Photo",
                pendingKind: .photo,
                ownDirectoryName: PhotoWidgetSnapshot.assetDirectoryName(assetId: assetId),
                snapshot: snapshot
            )

        case .album(let collectionId, let title):
            return resolve(
                designId: designId,
                sourceId: collectionId,
                title: title,
                pendingKind: .album,
                ownDirectoryName: PhotoWidgetSnapshot.albumDirectoryName(albumId: collectionId),
                snapshot: snapshot
            )
        }
    }

    /// The widget's own folder is preferred while it still holds this source —
    /// that is the one the app renders into when the source was chosen in the
    /// app, and it costs no second copy. Otherwise the per-source folder.
    private static func resolve(
        designId: String,
        sourceId: String,
        title: String,
        pendingKind: PendingSource.Kind,
        ownDirectoryName: String,
        snapshot: (String) -> PhotoWidgetSnapshot
    ) -> PhotoWidgetResolvedConfiguration {
        let own = snapshot(PhotoWidgetDesign.directoryName(id: designId))
        if !own.frames.isEmpty, own.sourceId == sourceId {
            return PhotoWidgetResolvedConfiguration(
                frameDirectoryName: PhotoWidgetDesign.directoryName(id: designId),
                pendingSource: nil
            )
        }
        let shared = snapshot(ownDirectoryName)
        if !shared.frames.isEmpty {
            return PhotoWidgetResolvedConfiguration(
                frameDirectoryName: ownDirectoryName,
                pendingSource: nil
            )
        }
        // A folder written before snapshots recorded what they were of: trust
        // it rather than blanking a widget that has been working all along.
        if !own.frames.isEmpty, own.sourceId == nil {
            return PhotoWidgetResolvedConfiguration(
                frameDirectoryName: PhotoWidgetDesign.directoryName(id: designId),
                pendingSource: nil
            )
        }
        return PhotoWidgetResolvedConfiguration(
            frameDirectoryName: ownDirectoryName,
            pendingSource: PendingSource(id: sourceId, title: title, kind: pendingKind)
        )
    }
}
