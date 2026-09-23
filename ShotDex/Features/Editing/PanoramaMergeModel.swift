import CoreImage
import os
import Photos
import ShotDexKit
import SwiftUI

/// What the panorama screen is doing, and what it can say about it.
enum PanoramaMergeState: Equatable {
    case loading(done: Int, total: Int)
    case stitching(String)
    /// A picture is on the stage.
    case ready
    /// Nothing overlapped anything. The one state where Save can never become
    /// available, so it carries the sentence rather than a spinner.
    case noOverlap
    /// Frames that would not come down from iCloud, with the count the screen
    /// puts in its message (FS-14.01 §2).
    case unavailable(count: Int)
    case failed(String)
}

/// Owns everything the panorama screen knows.
///
/// The screen draws; this decides. Registration and the solve run **once**,
/// when the screen opens — changing a projection or a size never re-runs them,
/// which is what makes those controls feel instant (FS-14.01 §4).
@MainActor
@Observable
final class PanoramaMergeModel {
    let assets: [PHAsset]

    private(set) var state: PanoramaMergeState = .loading(done: 0, total: 0)
    private(set) var preview: CGImage?
    /// True while the sharp version is being built behind the draft.
    private(set) var isRefining = false
    /// Frames that could not be joined to the panorama. Named on the screen,
    /// never dropped in silence.
    private(set) var unplaced: [Int] = []
    private(set) var saveProgress: Double?
    private(set) var savedAssetID: String?
    private(set) var errorMessage: String?

    var projection: PanoramaProjectionKind = .spherical {
        didSet { if projection != oldValue { schedulePreview(immediate: true) } }
    }
    var autoCrop = true {
        didSet { if autoCrop != oldValue { schedulePreview(immediate: true) } }
    }
    /// The Size control, 0.25…1. Does not change the picture, only what will be
    /// written — so it never redraws the stage.
    var sizeScale: Double = 1

    private(set) var availability: [PanoramaProjectionAvailability] = []

    private let photoLibrary: PhotoLibraryService
    private let stitch: PanoramaStitchService
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// Frames at preview resolution, and what registration made of them.
    private var previewSources: [PanoramaCISource] = []
    private var previewFocal: Double = 0
    private var cameras: [Int: PanoramaCamera] = [:]
    private var previewTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// Read from the stitch actor's thread, so it cannot live on the model:
    /// `isCancelled` is a synchronous callback and the main actor is not there
    /// to be assumed.
    private let isCancelledFlag = OSAllocatedUnfairLock(initialState: false)

    /// The long edge a preview is built at. The sharp tier of FS-14.01 §4.
    static let previewEdge = 1_536

    init(assets: [PHAsset], photoLibrary: PhotoLibraryService, stitch: PanoramaStitchService) {
        self.assets = assets.filter { $0.mediaType == .image }
        self.photoLibrary = photoLibrary
        self.stitch = stitch
    }

    /// Whether there is a panorama to adjust.
    ///
    /// The controls are hidden without one. A projection picker above a message
    /// saying these photos cannot be joined is three controls that change
    /// nothing, next to a Save that can never light up — the screen would be
    /// inviting work it has already refused.
    var hasPicture: Bool {
        if case .ready = state { return true }
        return preview != nil
    }

    var canSave: Bool {
        if case .ready = state { return saveProgress == nil }
        return false
    }

    var isSaving: Bool { saveProgress != nil }

    // MARK: Opening

    /// Loads proxies, finds the overlaps, solves, and puts a picture up.
    ///
    /// Everything expensive happens here once. What the panel does afterwards
    /// is re-project an answer that is already known.
    func load() async {
        guard assets.count >= 2 else {
            state = .noOverlap
            return
        }
        state = .loading(done: 0, total: assets.count)

        var images: [PanoramaImage] = []
        var sources: [PanoramaCISource] = []
        var missing = 0
        var pixelWidth = 0, pixelHeight = 0

        for (index, asset) in assets.enumerated() {
            state = .loading(done: index, total: assets.count)
            guard let proxy = await Self.proxyImage(for: asset, photoLibrary: photoLibrary),
                  let cgImage = proxy.cgImage,
                  let working = PanoramaImage.luminance(of: cgImage)
            else {
                missing += 1
                continue
            }
            pixelWidth = cgImage.width
            pixelHeight = cgImage.height
            images.append(working)
            sources.append(
                PanoramaCISource(
                    image: CIImage(cgImage: cgImage),
                    width: cgImage.width,
                    height: cgImage.height,
                    camera: PanoramaCamera(),
                    gain: 1
                )
            )
        }
        guard missing == 0 else {
            state = .unavailable(count: missing)
            return
        }
        guard images.count >= 2 else {
            state = .noOverlap
            return
        }

        state = .stitching(String(localized: "Finding overlaps…"))
        let registration: PanoramaRegistration
        do {
            registration = try PanoramaRegistrar.register(
                images: images, captureDates: assets.map(\.creationDate)
            )
        } catch {
            state = .noOverlap
            return
        }

        state = .stitching(String(localized: "Aligning…"))
        let solution = registration.solution
        guard solution.cameras.count >= 2 else {
            state = .noOverlap
            return
        }
        unplaced = solution.unplaced

        // Registration ran on the luminance image; the preview frames are the
        // proxy's own size, so the focal length comes back up with them.
        let scale = Double(pixelWidth) / Double(images[0].width)
        previewFocal = solution.focal * scale
        cameras = solution.cameras

        let gains = PanoramaGainSolver.gains(
            frameCount: images.count,
            overlaps: PanoramaGainMeasurement.overlaps(pairs: registration.pairs, images: images)
        )
        previewSources = solution.cameras.keys.sorted().compactMap { index in
            guard index < sources.count, let camera = solution.cameras[index] else { return nil }
            var source = sources[index]
            source.camera = camera
            source.gain = index < gains.count ? gains[index] : 1
            return source
        }

        availability = PanoramaProjection.availability(
            cameras: previewSources.map(\.camera),
            focal: previewFocal,
            imageWidth: pixelWidth,
            imageHeight: pixelHeight
        )
        if availability.first(where: { $0.kind == projection })?.isAvailable != true,
           let fallback = availability.first(where: \.isAvailable) {
            projection = fallback.kind
        }

        state = .stitching(String(localized: "Blending…"))
        await renderPreview(quality: .draft)
        state = .ready
        schedulePreview(immediate: false)
    }

    // MARK: Preview

    /// Redraws the stage. The draft goes up at once; the sharp version follows
    /// once nothing has changed for a moment, and a change in the meantime
    /// cancels it rather than queueing another.
    func schedulePreview(immediate: Bool) {
        guard !previewSources.isEmpty else { return }
        refineTask?.cancel()
        if immediate {
            previewTask?.cancel()
            previewTask = Task { [weak self] in
                await self?.renderPreview(quality: .draft)
                self?.scheduleRefine()
            }
        } else {
            scheduleRefine()
        }
    }

    private func scheduleRefine() {
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.isRefining = true
            await self?.renderPreview(quality: .sharp)
            self?.isRefining = false
        }
    }

    private func renderPreview(quality: PanoramaBlendQuality) async {
        guard !previewSources.isEmpty, previewFocal > 0 else { return }
        let sources = previewSources
        let focal = previewFocal
        let kind = projection
        let cropping = autoCrop
        let context = context

        let rendered: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let full = PanoramaProjection.canvas(
                kind: kind,
                cameras: sources.map(\.camera),
                focal: focal,
                imageWidth: sources[0].width,
                imageHeight: sources[0].height
            ) else { return nil }

            // Built at preview size rather than full and shrunk: a quarter-size
            // picture is about a sixteenth of the work.
            let longest = Double(max(full.width, full.height))
            let scale = min(1, Double(Self.previewEdge) / max(longest, 1))
            guard let canvas = PanoramaProjection.canvas(
                kind: kind,
                cameras: sources.map(\.camera),
                focal: focal,
                imageWidth: sources[0].width,
                imageHeight: sources[0].height,
                scale: scale
            ) else { return nil }

            let image: CIImage?
            switch quality {
            case .draft: image = PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)
            case .sharp: image = PanoramaCIBlender.sharp(canvas: canvas, sources: sources, focal: focal)
            }
            guard let image else { return nil }

            var extent = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
            if cropping, let crop = Self.cropRect(for: image, canvas: canvas, context: context) {
                extent = CGRect(
                    x: crop.x,
                    y: canvas.height - crop.y - crop.height,
                    width: crop.width,
                    height: crop.height
                )
            }
            return context.createCGImage(image, from: extent)
        }.value

        guard !Task.isCancelled, let rendered else { return }
        preview = rendered
    }

    /// The Auto Crop rectangle, read off the preview's own coverage.
    private nonisolated static func cropRect(
        for image: CIImage,
        canvas: PanoramaCanvas,
        context: CIContext
    ) -> PanoramaCropRect? {
        let width = canvas.width, height = canvas.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        var coverage = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let source = (height - 1 - y) * width
            for x in 0..<width {
                coverage[y * width + x] = rgba[4 * (source + x) + 3] > 0 ? 1 : 0
            }
        }
        return PanoramaAutoCrop.largestRectangle(coverage: coverage, width: width, height: height)
    }

    // MARK: Saving

    func save() {
        guard canSave else { return }
        isCancelledFlag.withLock { $0 = false }
        saveProgress = 0
        let options = PanoramaStitchOptions(
            projection: projection, sizeScale: sizeScale, autoCrop: autoCrop
        )
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identifier = try await stitch.stitch(
                    assets: assets,
                    options: options,
                    progress: { [weak self] phase in
                        Task { @MainActor in self?.apply(phase) }
                    },
                    isCancelled: { [weak self] in
                        self?.isCancelledFlag.withLock { $0 } ?? false
                    }
                )
                savedAssetID = identifier
            } catch PanoramaStitchError.cancelled {
                // Nothing was created, and nothing needs saying.
            } catch {
                errorMessage = Self.message(for: error)
            }
            saveProgress = nil
        }
    }

    func cancelSave() {
        isCancelledFlag.withLock { $0 = true }
        saveTask?.cancel()
    }

    func dismissError() { errorMessage = nil }

    private func apply(_ phase: PanoramaStitchPhase) {
        switch phase {
        case .writing(let fraction): saveProgress = fraction
        case .saving: saveProgress = 1
        default: break
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case PanoramaStitchError.framesUnavailable(let count):
            return String(
                localized: "\(count) photos couldn't be downloaded.",
                comment: "Panorama save failed because iCloud originals were unavailable"
            )
        case PanoramaStitchError.noOverlappingFrames:
            return String(localized: "Those photos don't overlap enough to join.")
        case PanoramaStitchError.projectionUnavailable:
            return String(localized: "That projection can't be built from these photos.")
        default:
            return String(localized: "The panorama couldn't be saved.")
        }
    }

    /// One frame at preview resolution, through the viewer's own request path
    /// so an iCloud-only original is fetched rather than skipped.
    private static func proxyImage(
        for asset: PHAsset,
        photoLibrary: PhotoLibraryService
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: CGSize(width: previewEdge, height: previewEdge),
                allowNetwork: true,
                progress: { _ in }
            ) { image, isDegraded in
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
