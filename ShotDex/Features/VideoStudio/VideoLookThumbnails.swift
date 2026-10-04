import CoreImage
import Photos
import SwiftUI
import ShotDexKit

/// The Look panel's tiles: the frame of the clip under the playhead under
/// each look (FS-12.06c §3).
///
/// One downscaled base frame, read without the network — a clip only in
/// iCloud on a device offline gets the looks' two-tone stand-ins, never a
/// download just to draw tiles. Each look then renders through the same
/// tables the compositor uses (its own small cache, so fifty tiles never
/// push the project's tables out), plus the vignette; grain and the
/// neighbourhood stages cannot be seen at 70pt and are left out. Tiles fill
/// in one by one on a background priority and stay until the playhead
/// moves to another clip.
@MainActor
@Observable
final class VideoLookThumbnails {
    private(set) var images: [String: UIImage] = [:]
    private(set) var baseAssetID: String?
    private var base: CGImage?
    private var queued: [String: VideoLook] = [:]
    private var renderTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    nonisolated private static let context = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated private static let tables = VideoLookTableCache(capacity: 8)

    /// Cancelled by the view on the way out; a nonisolated `deinit` cannot
    /// touch main-actor state.
    func cancel() {
        workTask?.cancel()
        renderTask?.cancel()
        renderTask = nil
        queued = [:]
    }

    /// Loads the base frame for the clip under the playhead, if it is not
    /// already the one the tiles show.
    func refresh(for model: VideoStudioModel, photoLibrary: PhotoLibraryService, cell: CGFloat) {
        guard let index = model.clipIndexUnderPlayhead, index < model.recipe.clips.count else { return }
        let assetID = model.recipe.clips[index].assetID
        guard assetID != baseAssetID else { return }
        baseAssetID = assetID
        base = nil
        images = [:]
        workTask?.cancel()
        renderTask?.cancel()
        renderTask = nil

        if let file = model.serverFileURL(for: assetID) {
            let side = Int(cell * 3)
            Task { [weak self] in
                guard let image = await PhotoOriginFile.loadImage(at: file, maxPixelSize: side),
                      self?.baseAssetID == assetID else { return }
                self?.setBase(image.cgImage)
            }
            return
        }
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: cell * 2, height: cell * 2),
            contentMode: .aspectFill,
            allowNetwork: false
        ) { [weak self] image, delivery in
            guard let self, delivery.isFinal, self.baseAssetID == assetID else { return }
            setBase(image?.cgImage)
        }
    }

    /// Asks for the tiles of `looks`, by tile id; ones already drawn stay.
    func request(_ looks: [(id: String, look: VideoLook)]) {
        for (id, look) in looks where images[id] == nil { queued[id] = look }
        drain()
    }

    private func setBase(_ image: CGImage?) {
        base = image
        drain()
    }

    private func drain() {
        guard let base, renderTask == nil, !queued.isEmpty else { return }
        let jobs = queued
        queued = [:]
        let assetID = baseAssetID
        let work = Task.detached(priority: .utility) { [weak self] in
            let source = CIImage(cgImage: base)
            for (id, look) in jobs {
                if Task.isCancelled { return }
                guard let rendered = Self.render(look, on: source) else { continue }
                await MainActor.run { [weak self] in
                    guard let self, self.baseAssetID == assetID else { return }
                    self.images[id] = rendered
                }
            }
        }
        workTask = work
        renderTask = Task { [weak self] in
            await work.value
            guard let self, !Task.isCancelled else { return }
            renderTask = nil
            drain()
        }
    }

    nonisolated private static func render(_ look: VideoLook, on source: CIImage) -> UIImage? {
        var tile = look
        // No grain and no neighbourhood stages at tile size (see above).
        if case let .myLook(id, name, imported, recipe) = look.source {
            var still = recipe
            still.adjustments.grain = 0
            tile = VideoLook(.myLook(sourceID: id, name: name, isImported: imported, recipe: still), amount: 1)
        } else {
            tile.amount = 1
        }
        let output: CIImage = if let plan = VideoLookPlan(tile, lutExists: VideoLookPlan.lutFileExists, policy: .skip) {
            VideoLookRenderer.apply(plan, to: source, cache: tables)
        } else {
            source
        }
        guard let picture = context.createCGImage(output, from: source.extent) else { return nil }
        return UIImage(cgImage: picture)
    }
}
