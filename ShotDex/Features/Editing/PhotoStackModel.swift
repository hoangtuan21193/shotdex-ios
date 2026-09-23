import Photos
import ShotDexKit
import SwiftUI

/// The state behind a Focus Stack or Stack Exposures screen: frames loaded
/// once, the preview for the mode in hand, and the save that turns it into a
/// new photo. The screen only draws it.
@MainActor
@Observable
final class PhotoStackModel {
    /// What went wrong, and when. The phase decides the alert title: a preview
    /// that failed has nothing to save yet, so it must not say "Couldn't Save".
    enum Failure: Equatable {
        case load(String)
        case save(String)

        var title: String {
            switch self {
            case .load: String(localized: "Couldn't Load Photos", comment: "Alert title: the frames for a stack could not be loaded or combined for the preview")
            case .save: String(localized: "Couldn't Save", comment: "Alert title: the combined photo could not be rendered or saved")
            }
        }

        var message: String {
            switch self {
            case .load(let text), .save(let text): text
            }
        }
    }

    let purpose: CombinePurpose
    let assets: [PHAsset]

    var mode: PhotoStackMode {
        didSet { if mode != oldValue { renderPreview() } }
    }
    private(set) var preview: UIImage?
    private(set) var isWorking = false
    private(set) var statusText: String?
    var failure: Failure?
    /// Frames the last combine left out because they would not line up
    /// (focus stack only), as indices into `assets`.
    private(set) var excludedFrames: [Int] = []
    /// Set once the new asset is saved, indexed and visible to the grid.
    private(set) var savedAssetID: String?

    /// Source frames at preview resolution, loaded once and reused for every
    /// mode change — reloading eight originals per picker tap is the difference
    /// between instant and unusable.
    private var previewFrames: [CIImage] = []
    private var renderTask: Task<Void, Never>?
    private let renderer = PhotoStackRenderer()
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline

    init(purpose: CombinePurpose, assets: [PHAsset], photoLibrary: PhotoLibraryService, indexPipeline: IndexPipeline) {
        self.purpose = purpose
        self.assets = assets
        self.mode = purpose.defaultMode ?? .average
        self.photoLibrary = photoLibrary
        self.indexPipeline = indexPipeline
    }

    var canSave: Bool { preview != nil && !isWorking }

    /// "2 of 40 frames couldn't be lined up and were left out." — nil when every
    /// frame made it in (FS-01.10 §4).
    var excludedFramesMessage: String? {
        guard !excludedFrames.isEmpty else { return nil }
        return String(
            localized: "\(excludedFrames.count) of \(previewFrames.count) frames couldn't be lined up and were left out.",
            comment: "Focus Stack panel: frames dropped because alignment failed. First number is dropped frames, second is all frames."
        )
    }

    /// Loads every frame once at preview resolution. Full resolution is left
    /// until Save: a thirty-frame macro stack at 48 megapixels is gigabytes, and
    /// nobody needs that to choose between Average and Lighten.
    func loadFrames() async {
        isWorking = true
        statusText = String(localized: "Loading \(assets.count) photos…", comment: "Stack screen status while the preview frames load")
        defer { isWorking = false }

        var frames: [CIImage] = []
        for asset in assets {
            guard let image = await Self.previewImage(for: asset, photoLibrary: photoLibrary),
                  let ciImage = CIImage(image: image) else { continue }
            frames.append(ciImage)
        }
        previewFrames = frames
        guard frames.count >= CombinePurpose.minimumPhotoCount else {
            failure = .load(PhotoStackError.needsTwoImages.localizedDescription)
            return
        }
        await render()
    }

    func cancel() { renderTask?.cancel() }

    private func renderPreview() {
        renderTask?.cancel()
        renderTask = Task { await render() }
    }

    private func render() async {
        guard previewFrames.count >= CombinePurpose.minimumPhotoCount else { return }
        isWorking = true
        statusText = workingText
        defer { isWorking = false }
        do {
            let result = try await renderer.combineReportingFrames(images: previewFrames, mode: mode)
            let cgImage = try await renderer.render(result.image)
            guard !Task.isCancelled else { return }
            preview = UIImage(cgImage: cgImage)
            excludedFrames = result.excludedFrames
        } catch {
            failure = .load(error.localizedDescription)
        }
    }

    private var workingText: String {
        mode.needsAlignment
            ? String(localized: "Lining frames up…", comment: "Stack screen status while frames are aligned")
            : String(localized: "Combining…", comment: "Stack screen status while frames are combined")
    }

    /// Re-runs the combine at full resolution and writes a new asset, then
    /// indexes it and tells the grid, so the viewer can open it straight away.
    /// The preview is not saved: it is a 1600pt proxy, and a photographer
    /// stacking macro frames wants every pixel they shot.
    func save() {
        renderTask?.cancel()
        renderTask = Task {
            isWorking = true
            statusText = String(localized: "Loading full-resolution frames…", comment: "Stack screen status while originals load for saving")
            defer { isWorking = false }
            do {
                var frames: [CIImage] = []
                for (index, asset) in assets.enumerated() {
                    statusText = String(localized: "Loading \(index + 1) of \(assets.count)…", comment: "Stack screen status while originals load, one by one")
                    guard let data = await Self.originalData(for: asset),
                          let image = CIImage(data: data)
                    else { continue }
                    frames.append(image)
                }
                guard frames.count >= CombinePurpose.minimumPhotoCount else { throw PhotoStackError.needsTwoImages }

                statusText = workingText
                let combined = try await renderer.combine(images: frames, mode: mode)
                let cgImage = try await renderer.render(combined)

                statusText = String(localized: "Saving…", comment: "Stack screen status while the new photo is written")
                guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.98) else {
                    throw PhotoStackError.renderFailed
                }
                let name = "ShotDex-\(mode.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
                let assetID = try await photoLibrary.saveImage(data, filename: name)
                _ = await indexPipeline.indexSingle(assetId: assetID)
                photoLibrary.publishAppCreatedAsset()
                savedAssetID = assetID
            } catch {
                failure = .save(error.localizedDescription)
            }
        }
    }
}

extension PhotoStackModel {
    /// One frame at proxy resolution, through the viewer's own request path so
    /// an iCloud-only original is fetched rather than skipped.
    static func previewImage(for asset: PHAsset, photoLibrary: PhotoLibraryService) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                allowNetwork: true,
                progress: { _ in }
            ) { image, isDegraded in
                // The request calls back more than once as better data lands;
                // take the first final one and ignore the rest.
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// The original file's bytes, for the full-resolution pass at save time.
    static func originalData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
