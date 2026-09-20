import CoreImage
import Photos
import SwiftUI
import ShotDexKit

/// Thumbnails of the project's own frame under each look.
///
/// The Effects tab listed 49 looks as 49 identical glyphs, so picking one
/// meant reading names and guessing. Resolve's Effects tab shows what the
/// thing does. This renders the clip under the playhead through every filter
/// once, at cell size, and keeps the results.
///
/// It is cheap because it is small and done once: one downscaled base frame,
/// 49 `CIFilter` chains at ~90pt, on a background priority, cached until the
/// base frame changes. Nothing here runs per scroll or per frame.
@MainActor
@Observable
final class VideoFilterThumbnails {
    private(set) var images: [PhotoFilter: UIImage] = [:]
    /// Which asset the current set was rendered from, so moving the playhead
    /// to a different clip refreshes them and moving it within one does not.
    private(set) var baseAssetID: String?

    private var renderTask: Task<Void, Never>?
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Cancelled by the view on the way out; a nonisolated `deinit` cannot
    /// touch main-actor state.
    func cancel() {
        renderTask?.cancel()
        renderTask = nil
    }

    /// Renders the set for the clip under the playhead, if it is not already
    /// the one on screen.
    func refresh(for model: VideoStudioModel, photoLibrary: PhotoLibraryService, cell: CGFloat) {
        guard let index = model.clipIndexUnderPlayhead,
              index < model.recipe.clips.count
        else { return }
        let assetID = model.recipe.clips[index].assetID
        guard assetID != baseAssetID else { return }
        baseAssetID = assetID
        images = [:]
        renderTask?.cancel()

        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
        let target = CGSize(width: cell * 2, height: cell * 2)
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            allowNetwork: false
        ) { [weak self] image, delivery in
            guard let self, delivery.isFinal, let image else { return }
            render(base: image)
        }
    }

    private func render(base: UIImage) {
        guard let cg = base.cgImage else { return }
        renderTask?.cancel()
        renderTask = Task(priority: .utility) { [weak self] in
            let source = CIImage(cgImage: cg)
            for filter in PhotoFilter.allCases {
                if Task.isCancelled { return }
                let output = PhotoRenderService.applyFilter(filter, intensity: 1, to: source)
                guard let rendered = Self.context.createCGImage(output, from: source.extent) else { continue }
                let image = UIImage(cgImage: rendered)
                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    images[filter] = image
                }
            }
        }
    }
}
