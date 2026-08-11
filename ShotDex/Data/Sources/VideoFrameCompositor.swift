import AVFoundation
import CoreImage
import Photos
import UIKit

/// The per-frame render settings shared by every instruction of one build.
/// A value snapshot: editing the recipe mid-preview swaps the whole
/// `AVVideoComposition`, never mutates a live instruction.
struct VideoRenderRecipe: Sendable {
    let filter: PhotoFilter
    let filterIntensity: Double
    let adjustments: PhotoAdjustments
    let overlays: [TimedOverlay]
    let renderSize: CGSize
    let totalDuration: Double
    /// Letterbox / pillarbox fill behind aspect-fitted frames.
    let background: CIColor

    init(recipe: VideoProjectRecipe, renderSize: CGSize, totalDuration: Double) {
        self.filter = recipe.filter
        self.filterIntensity = recipe.filterIntensity
        self.adjustments = recipe.adjustments
        self.overlays = recipe.overlays
        self.renderSize = renderSize
        self.totalDuration = totalDuration
        self.background = CIColor(
            red: recipe.background.red,
            green: recipe.background.green,
            blue: recipe.background.blue
        )
    }

    var hasWork: Bool {
        filter != .original || !adjustments.isIdentity || !overlays.isEmpty
    }

    /// The overlays visible at `time`, in recipe order.
    func activeOverlays(at time: Double) -> [PhotoOverlay] {
        overlays
            .filter { $0.isActive(at: time, total: totalDuration) }
            .map(\.overlay)
    }
}

/// Serves still photos to the compositor. Loads synchronously off-main via
/// PHImageManager (the compositor's frame queue is never the main thread),
/// downsampled to the render size, behind an NSLock'd LRU of 4 — a 3840-long-
/// edge BGRA still is ~33 MB, so caching every clip of a 20-photo slideshow
/// would cost hundreds of MB for pixels the timeline may never revisit.
final class StillFrameStore: @unchecked Sendable {
    private let targetLongEdge: CGFloat
    private let lock = NSLock()
    private var cache: [String: CIImage] = [:]
    private var order: [String] = []
    private let capacity = 4

    init(targetLongEdge: CGFloat) {
        self.targetLongEdge = targetLongEdge
    }

    func image(for assetID: String) -> CIImage? {
        lock.lock()
        if let cached = cache[assetID] {
            order.removeAll { $0 == assetID }
            order.append(assetID)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let loaded = load(assetID) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        cache[assetID] = loaded
        order.append(assetID)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return loaded
    }

    private func load(_ assetID: String) -> CIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        var result: CIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetLongEdge, height: targetLongEdge),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let cgImage = image?.cgImage {
                result = CIImage(cgImage: cgImage)
            }
        }
        return result
    }
}

/// One segment of the timeline for the custom compositor: a passthrough
/// window over a single clip, or a crossfade window over two.
final class VideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    /// Where a segment's pixels come from.
    enum Source {
        /// A composition video track, with the clip's full fit transform
        /// (orientation + rotation + aspect-fit), expressed in video space
        /// (top-left origin) — the compositor adds the CI y-flip sandwich.
        case track(id: CMPersistentTrackID, transform: CGAffineTransform)
        /// A still photo, drawn by the compositor into `fitRect` on the
        /// canvas. The track underneath is an empty time range.
        case still(assetID: String, fitRect: CGRect)
        /// An already-loaded still (a freeze frame), drawn into `fitRect`.
        /// Bypasses the PHAsset-backed `StillFrameStore`.
        case stillImage(image: CIImage, fitRect: CGRect)
    }

    /// A source clip's placement timing + effect: everything a per-clip
    /// effect needs to compute its clip-local progress at a frame time.
    struct ClipRenderTiming: Sendable {
        let clipIndex: Int
        let start: Double
        let duration: Double
        let effect: VideoClipEffect
    }

    let timeRange: CMTimeRange
    let front: Source
    let frontClip: ClipRenderTiming
    /// The outgoing clip during a transition; nil for passthrough segments.
    let back: Source?
    let backClip: ClipRenderTiming?
    let fadeStart: Double
    let fadeDuration: Double
    let transitionKind: VideoTransitionKind
    let recipe: VideoRenderRecipe
    let stillStore: StillFrameStore

    init(
        timeRange: CMTimeRange,
        front: Source,
        frontClip: ClipRenderTiming,
        back: Source?,
        backClip: ClipRenderTiming?,
        fadeStart: Double,
        fadeDuration: Double,
        transitionKind: VideoTransitionKind,
        recipe: VideoRenderRecipe,
        stillStore: StillFrameStore
    ) {
        self.timeRange = timeRange
        self.front = front
        self.frontClip = frontClip
        self.back = back
        self.backClip = backClip
        self.fadeStart = fadeStart
        self.fadeDuration = fadeDuration
        self.transitionKind = transitionKind
        self.recipe = recipe
        self.stillStore = stillStore
    }

    var enablePostProcessing: Bool { true }
    /// Fades and per-frame filters animate; claiming no tweening lets AVF
    /// collapse the segment to one frame.
    var containsTweening: Bool { true }

    var requiredSourceTrackIDs: [NSValue]? {
        var ids: [NSValue] = []
        if case .track(let id, _) = front { ids.append(NSNumber(value: id)) }
        if case .track(let id, _) = back { ids.append(NSNumber(value: id)) }
        return ids
    }

    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }
}

/// The custom video compositor: resolves each request's source frames
/// (track pixels or cached stills), dissolves crossfades, applies the global
/// filter/adjustments, composites the rasterized text overlay, and renders
/// BGRA into the context's pixel buffer pool.
///
/// The render chain is `LivePhotoFrameRenderer`'s (PhotoEditingService.swift)
/// with the frame source swapped: the same non-isolated static
/// `PhotoRenderService` steps, and the same rasterize-once overlay cache.
final class VideoFrameCompositor: NSObject, AVVideoCompositing {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .name: "ShotDex Video Compositor",
    ])
    private let overlayLock = NSLock()
    /// Keyed by extent AND overlay content: the compositor instance outlives
    /// `videoComposition` swaps (AVF creates it per player item / export
    /// session), so an overlay edit must invalidate the cached layer.
    private var overlayLayer: (extent: CGRect, overlays: [PhotoOverlay], image: CIImage)?

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: VideoCompositorError.badInstruction)
            return
        }

        let renderSize = request.renderContext.size
        let canvas = CGRect(origin: .zero, size: renderSize)
        let seconds = request.compositionTime.seconds
        let backgroundImage = CIImage(color: instruction.recipe.background).cropped(to: canvas)

        guard var image = resolvedImage(
            instruction.front,
            request: request,
            renderSize: renderSize
        ) else {
            // A missing still or dropped frame renders the background rather
            // than failing the whole export.
            render(backgroundImage, to: output, request: request)
            return
        }

        // Per-clip effects run on each side independently, before the blend:
        // during a transition the outgoing clip's blur-out plays against the
        // incoming clip's blur-in, each on its own placement clock.
        image = applyClipEffect(image, timing: instruction.frontClip, at: seconds, canvas: canvas)

        if let back = instruction.back,
           var outgoing = resolvedImage(back, request: request, renderSize: renderSize) {
            if let backClip = instruction.backClip {
                outgoing = applyClipEffect(outgoing, timing: backClip, at: seconds, canvas: canvas)
            }
            let progress = VideoTimelineMath.fadeProgress(
                at: seconds,
                fadeStart: instruction.fadeStart,
                duration: instruction.fadeDuration
            )
            image = blend(
                front: image.cropped(to: canvas),
                back: outgoing.cropped(to: canvas),
                kind: instruction.transitionKind,
                progress: progress,
                canvas: canvas,
                background: backgroundImage
            )
        }

        // Letterbox bars: undefined pixels outside the fitted frame take the
        // recipe background, and the canvas extent is pinned before the filter
        // chain.
        image = image.composited(over: backgroundImage)
            .cropped(to: canvas)

        let recipe = instruction.recipe
        if recipe.hasWork {
            image = PhotoRenderService.applyAdjustments(
                recipe.adjustments,
                to: image,
                appliesExposure: true
            )
            image = PhotoRenderService.applyFilter(
                recipe.filter,
                intensity: recipe.filterIntensity,
                to: image
            )
            let active = recipe.activeOverlays(at: seconds)
            if let layer = cachedOverlayLayer(overlays: active, extent: canvas) {
                image = layer.composited(over: image)
            }
            image = image.cropped(to: canvas)
        }

        render(image, to: output, request: request)
    }

    // MARK: - Per-clip effects

    /// The clip effect at this frame, evaluated on the fitted image in canvas
    /// coordinates. Geometric effects are one affine; optics reuse the
    /// photo pipeline's extent-safe primitives.
    private func applyClipEffect(
        _ image: CIImage,
        timing: VideoCompositionInstruction.ClipRenderTiming,
        at time: Double,
        canvas: CGRect
    ) -> CIImage {
        switch timing.effect {
        case .none:
            return image
        case .zoomIn, .zoomOut, .panLeft, .panRight, .shake:
            let transform = VideoEffectMath.effectTransform(
                effect: timing.effect,
                progress: VideoEffectMath.clipProgress(
                    time: time, clipStart: timing.start, clipDuration: timing.duration
                ),
                time: time,
                clipStart: timing.start,
                clipDuration: timing.duration,
                clipIndex: timing.clipIndex,
                renderSize: canvas.size
            )
            return transform.isIdentity ? image : image.transformed(by: transform)
        case .blurIn, .blurOut:
            let radius = VideoEffectMath.effectBlurRadius(
                effect: timing.effect,
                time: time,
                clipStart: timing.start,
                clipDuration: timing.duration,
                renderSize: canvas.size
            )
            guard radius > 0.01 else { return image }
            return PhotoRenderService.blurred(image, radius: radius)
        case .softGlow:
            let glow = PhotoRenderService.blurred(
                image,
                radius: VideoEffectMath.glowRadius(renderSize: canvas.size)
            )
            let dimmedGlow = PhotoRenderService.filtered(
                "CIColorMatrix",
                image: glow,
                values: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: VideoEffectMath.glowIntensity),
                ]
            )
            return PhotoRenderService.filtered(
                "CIScreenBlendMode",
                image: dimmedGlow,
                values: [kCIInputBackgroundImageKey: image]
            ).cropped(to: image.extent)
        case .vignettePulse:
            let local = max(0, time - timing.start)
            return PhotoRenderService.filtered(
                "CIVignetteEffect",
                image: image,
                values: [
                    kCIInputCenterKey: CIVector(x: canvas.midX, y: canvas.midY),
                    kCIInputIntensityKey: VideoEffectMath.vignettePulseIntensity(localTime: local),
                    kCIInputRadiusKey: VideoEffectMath.vignetteRadius(renderSize: canvas.size),
                ]
            )
        }
    }

    // MARK: - Transitions

    /// Blend the incoming (`front`) over the outgoing (`back`) frame. Both
    /// arrive cropped to the canvas.
    private func blend(
        front: CIImage,
        back: CIImage,
        kind: VideoTransitionKind,
        progress: Double,
        canvas: CGRect,
        background: CIImage
    ) -> CIImage {
        // Fade-to-*black* is literal by name; slide/zoom expose the recipe
        // background where a frame has slid away.
        let black = CIImage(color: .black).cropped(to: canvas)
        let fill = background
        switch kind {
        case .fadeBlack:
            let (stage, t) = VideoEffectMath.fadeBlackStage(progress: progress)
            switch stage {
            case .out:
                return dissolve(from: back, to: black, progress: t)
            case .in:
                return dissolve(from: black, to: front, progress: t)
            }
        case .slideLeft, .slideRight:
            let offsets = VideoEffectMath.slideOffsets(
                kind: kind, progress: progress, renderSize: canvas.size
            )
            let movedFront = front
                .transformed(by: CGAffineTransform(translationX: offsets.front.dx, y: 0))
                .cropped(to: canvas)
            let movedBack = back
                .transformed(by: CGAffineTransform(translationX: offsets.back.dx, y: 0))
                .cropped(to: canvas)
            return movedFront.composited(over: movedBack.composited(over: fill))
        case .wipe:
            let sweep = VideoEffectMath.wipeGradientX(
                progress: progress, width: canvas.width
            )
            // CILinearGradient is a generator (no inputImage), so it can't go
            // through `PhotoRenderService.filtered` — that wrapper always sets
            // kCIInputImageKey, and an undefined key raises.
            let gradient = CIFilter(name: "CILinearGradient")
            gradient?.setValue(CIVector(x: sweep.whiteX, y: canvas.midY), forKey: "inputPoint0")
            gradient?.setValue(CIVector(x: sweep.blackX, y: canvas.midY), forKey: "inputPoint1")
            gradient?.setValue(CIColor.white, forKey: "inputColor0")
            gradient?.setValue(CIColor.black, forKey: "inputColor1")
            guard let mask = gradient?.outputImage?.cropped(to: canvas) else {
                return dissolve(from: back, to: front, progress: progress)
            }
            return PhotoRenderService.filtered(
                "CIBlendWithMask",
                image: front,
                values: [
                    kCIInputBackgroundImageKey: back,
                    kCIInputMaskImageKey: mask,
                ]
            ).cropped(to: canvas)
        case .zoom:
            let scale = VideoEffectMath.zoomTransitionScale(progress: progress)
            let center = CGPoint(x: canvas.midX, y: canvas.midY)
            let scaledBack = back
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -center.x, y: -center.y))
                .cropped(to: canvas)
            return dissolve(from: scaledBack, to: front, progress: progress)
        case .crossfade, .none:
            // `.none` never reaches a fade segment; crossfade is the
            // defensive default.
            return dissolve(from: back, to: front, progress: progress)
        }
    }

    private func dissolve(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        PhotoRenderService.filtered(
            "CIDissolveTransition",
            image: from,
            values: [
                kCIInputTargetImageKey: to,
                kCIInputTimeKey: progress,
            ]
        )
    }

    private func render(
        _ image: CIImage,
        to buffer: CVPixelBuffer,
        request: AVAsynchronousVideoCompositionRequest
    ) {
        context.render(image, to: buffer)
        request.finish(withComposedVideoFrame: buffer)
    }

    /// A source's pixels on the canvas. Track transforms were computed in
    /// video space (top-left origin); Core Image is bottom-left, so the
    /// transform is applied inside a y-flip sandwich — flip into video space,
    /// transform, flip back at canvas height.
    private func resolvedImage(
        _ source: VideoCompositionInstruction.Source,
        request: AVAsynchronousVideoCompositionRequest,
        renderSize: CGSize
    ) -> CIImage? {
        switch source {
        case .track(let id, let transform):
            guard let buffer = request.sourceFrame(byTrackID: id) else { return nil }
            let image = CIImage(cvPixelBuffer: buffer)
            let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: image.extent.height)
            let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
            return image.transformed(by: flipIn.concatenating(transform).concatenating(flipOut))
        case .still(let assetID, let fitRect):
            guard let image = stillImage(assetID: assetID, request: request) else { return nil }
            return placedStill(image, in: fitRect)
        case .stillImage(let image, let fitRect):
            return placedStill(image, in: fitRect)
        }
    }

    /// Scale a still into its centred `fitRect`. `fitRect` is centred on the
    /// canvas, so it reads the same in either vertical convention — no flip.
    private func placedStill(_ image: CIImage, in fitRect: CGRect) -> CIImage? {
        guard image.extent.width > 0 else { return nil }
        let scale = fitRect.width / image.extent.width
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(
                    translationX: fitRect.minX - image.extent.minX * scale,
                    y: fitRect.minY - image.extent.minY * scale
                )))
    }

    private func stillImage(
        assetID: String,
        request: AVAsynchronousVideoCompositionRequest
    ) -> CIImage? {
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction
        else { return nil }
        return instruction.stillStore.image(for: assetID)
    }

    /// Rasterized once per build (extent never changes between frames) —
    /// the exact reason `PhotoRenderService.overlayLayer` is exposed.
    private func cachedOverlayLayer(overlays: [PhotoOverlay], extent: CGRect) -> CIImage? {
        guard !overlays.isEmpty else { return nil }
        overlayLock.lock()
        defer { overlayLock.unlock() }
        if let overlayLayer, overlayLayer.extent == extent, overlayLayer.overlays == overlays {
            return overlayLayer.image
        }
        guard let layer = PhotoRenderService.overlayLayer(overlays, extent: extent) else { return nil }
        overlayLayer = (extent, overlays, layer)
        return layer
    }
}

enum VideoCompositorError: Error {
    case badInstruction
}
