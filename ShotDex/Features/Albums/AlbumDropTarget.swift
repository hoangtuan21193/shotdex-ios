import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Makes an album token accept photos dragged from a grid.
///
/// A drop only ever *adds* to the album — the photos stay where they were, and
/// nothing is moved or deleted. That is what dragging onto an album means in
/// Photos, and it is the only reading that is safe to perform without asking.
struct AlbumDropTarget: ViewModifier {
    let collection: PHAssetCollection?
    let photoLibrary: PhotoLibraryService
    /// Called after a successful add, so the token's count can refresh.
    let onAdded: () -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .strokeBorder(AppAccent.color, lineWidth: 2)
                }
            }
            .dropDestination(for: PhotoDropPayload.self) { payloads, _ in
                accept(payloads)
            } isTargeted: { targeted in
                // Only light up for an album that can actually take them —
                // a smart album highlighting and then refusing is a lie.
                isTargeted = targeted && canAccept
            }
    }

    private var canAccept: Bool {
        collection?.canPerform(.addContent) == true
    }

    private func accept(_ payloads: [PhotoDropPayload]) -> Bool {
        guard canAccept, let collection else { return false }
        let ids = payloads.map(\.assetIdentifier)
        guard !ids.isEmpty else { return false }
        Task {
            let assets = PhotoLibraryService.fetchAssets(ids: ids)
            guard !assets.isEmpty else { return }
            try? await photoLibrary.addAssets(assets, to: collection)
            onAdded()
        }
        return true
    }
}

/// One dragged photo, as SwiftUI's drop machinery sees it: the asset's local
/// identifier and nothing else.
///
/// A private type identifier, matching the one `PhotoDragItem` registers, so a
/// drag from another app cannot land here and a drag from here offers no other
/// app something that would mean nothing to it.
struct PhotoDropPayload: Transferable, Sendable {
    let assetIdentifier: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .shotDexAssetIdentifier) { payload in
            Data(payload.assetIdentifier.utf8)
        } importing: { data in
            PhotoDropPayload(assetIdentifier: String(decoding: data, as: UTF8.self))
        }
    }
}

extension UTType {
    static let shotDexAssetIdentifier = UTType(
        exportedAs: PhotoDragItem.assetIdentifierType
    )
}

extension View {
    /// Accepts photos dragged onto this album token.
    func albumDropTarget(
        collection: PHAssetCollection?,
        photoLibrary: PhotoLibraryService,
        onAdded: @escaping () -> Void
    ) -> some View {
        modifier(
            AlbumDropTarget(
                collection: collection,
                photoLibrary: photoLibrary,
                onAdded: onAdded
            )
        )
    }
}
