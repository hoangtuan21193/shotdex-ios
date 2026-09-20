import CoreImage
import Photos
import SwiftUI
import ShotDexKit

/// Keeps one scope picture up to date for the clip under the playhead.
///
/// The base frame is fetched once per clip and held; a grade change only
/// re-runs the colour chain and the counting, both on a background task, so
/// dragging a wheel repaints the scope without touching PhotoKit.
///
/// It measures the **graded** frame — `VideoRenderRecipe.graded(_:)`, the
/// same chain the compositor runs — because a scope reading the source
/// would tell the colourist about the camera, not about their grade.
@MainActor
@Observable
final class VideoScopeModel {
    var kind: VideoScopeKind = .waveform {
        didSet { if kind != oldValue { rerender() } }
    }

    private(set) var image: CGImage?

    /// The clip whose frame is loaded, and the grade the picture on screen
    /// was counted from — the two things that make the scope stale.
    private var baseAssetID: String?
    private var renderedGrade: GradeKey?
    private var base: CIImage?
    private var pendingRecipe: VideoProjectRecipe?
    private var renderTask: Task<Void, Never>?

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Cancelled by the view on the way out; a nonisolated `deinit` cannot
    /// touch main-actor state.
    func cancel() {
        renderTask?.cancel()
        renderTask = nil
    }

    func refresh(for model: VideoStudioModel, photoLibrary: PhotoLibraryService) {
        guard let index = model.clipIndexUnderPlayhead,
              index < model.recipe.clips.count
        else { return }
        let assetID = model.recipe.clips[index].assetID
        pendingRecipe = model.recipe
        guard assetID != baseAssetID else {
            rerenderIfGradeChanged()
            return
        }
        baseAssetID = assetID
        base = nil
        renderedGrade = nil
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 480, height: 480),
            contentMode: .aspectFit,
            allowNetwork: false
        ) { [weak self] image, delivery in
            guard let self, delivery.isFinal, let cg = image?.cgImage else { return }
            base = CIImage(cgImage: cg)
            rerender()
        }
    }

    private func rerenderIfGradeChanged() {
        guard let recipe = pendingRecipe else { return }
        guard GradeKey(recipe) != renderedGrade else { return }
        rerender()
    }

    private func rerender() {
        guard let base, let recipe = pendingRecipe else { return }
        renderedGrade = GradeKey(recipe)
        renderTask?.cancel()
        let kind = kind
        renderTask = Task(priority: .utility) { [weak self] in
            let render = VideoRenderRecipe(
                recipe: recipe,
                renderSize: base.extent.size,
                totalDuration: 1,
                bakesOverlays: false
            )
            let graded = render.hasWork ? render.graded(base) : base
            guard !Task.isCancelled,
                  let sample = VideoScopeRenderer.sample(graded, context: Self.context),
                  !Task.isCancelled,
                  let picture = VideoScopeRenderer.image(
                    kind: kind,
                    rgba: sample.rgba,
                    width: sample.width,
                    height: sample.height
                  )
            else { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                image = picture
            }
        }
    }

    /// Everything the colour chain reads, as one comparable value. Cheap to
    /// build on every view update, and it is the only thing that decides
    /// whether the counting runs again — the kit's recipe types are
    /// `Equatable`, so this compares rather than hashes.
    private struct GradeKey: Equatable {
        let inputTransform: VideoInputTransform
        let filter: PhotoFilter
        let filterIntensity: Double
        let adjustments: PhotoAdjustments
        let color: PhotoColorRecipe
        let curve: ToneCurveAdjustments
        let masks: [PhotoMask]
        let lut: VideoLUTReference?

        init(_ recipe: VideoProjectRecipe) {
            inputTransform = recipe.inputTransform
            filter = recipe.filter
            filterIntensity = recipe.filterIntensity
            adjustments = recipe.adjustments
            color = recipe.color
            curve = recipe.curve
            masks = recipe.masks
            lut = recipe.lut
        }
    }
}
