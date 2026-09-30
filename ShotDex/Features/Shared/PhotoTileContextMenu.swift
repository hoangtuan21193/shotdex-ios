import Photos
import UIKit

/// The long-press menu on a single grid tile, modelled on the one iOS Photos
/// shows: the tile lifts into a preview and the actions that make sense for one
/// photo hang off it.
///
/// A `UIMenu` rather than SwiftUI's `.contextMenu` because the grid is a
/// `UICollectionView`; the menu is built here once and handed to every screen
/// that shows a grid, so Library, Album Detail, Smart Album Detail and On This
/// Day cannot drift apart.
///
/// Rows whose closure is `nil` are omitted — Album Detail is the only screen
/// with "Remove from Album", On This Day is the only one with "Show in Library".
@MainActor
struct PhotoTileContextMenu {
    let assetId: String
    let isVideo: Bool
    let actions: AssetActionsCoordinator

    var onShare: () -> Void
    var onAddToCollection: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onEdit: (() -> Void)?
    var onShowInLibrary: (() -> Void)?
    var onRemoveFromAlbum: (() -> Void)?

    private var asset: PHAsset? {
        PhotoLibraryService.fetchAssets(ids: [assetId]).first
    }

    func makeMenu() -> UIMenu {
        let isFavorite = asset?.isFavorite ?? false
        var primary: [UIMenuElement] = []

        primary.append(
            UIAction(
                title: isFavorite ? "Unfavorite" : "Favorite",
                image: UIImage(systemName: isFavorite ? "heart.slash" : "heart")
            ) { _ in
                actions.setFavorite(!isFavorite, ids: [assetId])
            }
        )
        if let onEdit {
            primary.append(
                UIAction(title: PhotoCommand.edit.title, image: UIImage(systemName: PhotoCommand.edit.systemImage)) { _ in
                    onEdit()
                }
            )
        }
        primary.append(
            UIAction(title: PhotoCommand.share.title, image: UIImage(systemName: PhotoCommand.share.systemImage)) { _ in
                onShare()
            }
        )
        // A video's frames are not something the pasteboard can hold.
        if !isVideo {
            primary.append(
                UIAction(title: PhotoCommand.copy.title, image: UIImage(systemName: PhotoCommand.copy.systemImage)) { _ in
                    actions.copyToPasteboard(id: assetId)
                }
            )
        }

        let organise: [UIMenuElement] = [
            UIAction(
                title: PhotoCommand.addToCollection.title,
                image: UIImage(systemName: PhotoCommand.addToCollection.systemImage)
            ) { _ in onAddToCollection() },
            UIAction(
                title: PhotoCommand.duplicate.title,
                image: UIImage(systemName: PhotoCommand.duplicate.systemImage)
            ) { _ in onDuplicate() },
            UIAction(
                title: "Adjust Date & Time",
                image: UIImage(systemName: "calendar")
            ) { _ in actions.presentAdjustDate(ids: [assetId]) },
            UIAction(
                title: "Adjust Location",
                image: UIImage(systemName: "mappin.and.ellipse")
            ) { _ in actions.presentAdjustLocation(ids: [assetId]) },
        ]

        var destructive: [UIMenuElement] = []
        if let onShowInLibrary {
            destructive.append(
                UIAction(
                    title: "Show in Library",
                    image: UIImage(systemName: "photo.on.rectangle.angled")
                ) { _ in onShowInLibrary() }
            )
        }
        destructive.append(
            UIAction(
                title: "Hide",
                image: UIImage(systemName: "eye.slash"),
                attributes: .destructive
            ) { _ in actions.toggleHidden(ids: [assetId]) }
        )
        if let onRemoveFromAlbum {
            destructive.append(
                UIAction(
                    title: "Remove from Album",
                    image: UIImage(systemName: "minus.circle"),
                    attributes: .destructive
                ) { _ in onRemoveFromAlbum() }
            )
        }
        destructive.append(
            UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in onDelete() }
        )

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: primary),
            UIMenu(options: .displayInline, children: organise),
            UIMenu(options: .displayInline, children: destructive),
        ])
    }
}
