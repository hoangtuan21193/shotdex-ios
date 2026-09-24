import CoreImage
import ImageIO
import os
import Photos
import ShotDexKit
import SwiftUI
import UniformTypeIdentifiers

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
    /// How hard the picture is stretched out to the rectangle, 0…1
    /// (FS-14.02 §5). Zero by default: a stretch is a change to the
    /// photograph, and the photographer asks for it.
    var boundaryWarp: Double = 0 {
        didSet { if boundaryWarp != oldValue { schedulePreview(immediate: true) } }
    }

    private(set) var availability: [PanoramaProjectionAvailability] = []

    private let photoLibrary: PhotoLibraryService
    private let stitch: PanoramaStitchService
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// Frames at preview resolution, and what registration made of them.
    private var previewSources: [PanoramaCISource] = []
    /// What Arrange needs to put a frame back: the working-size frames the
    /// registration ran on, every overlap it found, and the full-size sources
    /// in frame order (`previewSources` holds only the placed ones).
    private var workingImages: [PanoramaImage] = []
    private var pairs: [PanoramaPairObservation] = []
    private var solution: PanoramaCameraSolution?
    private var thumbnails: [Int: CGImage] = [:]
    private var allSources: [PanoramaCISource] = []
    private var previewFocal: Double = 0
    /// Working-size frames to preview-size frames: registration runs small,
    /// everything the screen shows is the proxy's own resolution.
    private var previewScale: Double = 1
    private var previewWidth = 0
    private var previewHeight = 0
    private var cameras: [Int: PanoramaCamera] = [:]
    private var previewTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// Read from the stitch actor's thread, so it cannot live on the model:
    /// `isCancelled` is a synchronous callback and the main actor is not there
    /// to be assumed.
    private let isCancelledFlag = OSAllocatedUnfairLock(initialState: false)

    /// The picture at the frames' own resolution, Auto Crop already taken off
    /// — the size Size is a percentage of.
    private var fullOutputWidth = 0
    private var fullOutputHeight = 0
    /// The same picture before Auto Crop — what the renderer draws, and so
    /// what the JPEG edge limit applies to.
    private var fullCanvasWidth = 0
    private var fullCanvasHeight = 0
    /// The canvas the preview on screen was built with, and the part of it
    /// that is showing — what turns a point on the stage into a direction.
    private var previewCanvas: PanoramaCanvas?
    private var previewCrop: PanoramaCropRect?
    /// Measured on the sharp preview, not assumed (FS-14.01 §4b).
    private var bytesPerPixel: Double?
    private var secondsPerMegapixel: Double?

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
        guard case .ready = state, saveProgress == nil else { return false }
        return spaceShortfall == nil
    }

    // MARK: What it will cost

    /// The size, file and wait the current settings produce, or nil until a
    /// sharp preview has been measured.
    var sizeEstimate: PanoramaSizeEstimate? {
        guard let bytesPerPixel, let secondsPerMegapixel else { return nil }
        return PanoramaSizeEstimator.estimate(
            fullWidth: fullOutputWidth,
            fullHeight: fullOutputHeight,
            canvasWidth: fullCanvasWidth,
            canvasHeight: fullCanvasHeight,
            sizeScale: sizeScale,
            bytesPerPixel: bytesPerPixel,
            secondsPerMegapixel: secondsPerMegapixel
        )
    }

    /// How many bytes short the device is, or nil when there is room (or when
    /// the volume cannot be read, in which case no warning is better than a
    /// wrong one).
    var spaceShortfall: Int64? {
        guard let sizeEstimate, let available = DiskSpace.availableBytes() else { return nil }
        let needed = PanoramaSizeEstimator.requiredFreeBytes(for: sizeEstimate)
        return needed > available ? needed - available : nil
    }

    /// The one line under the Size slider (FS-14.01 §4b).
    var estimateText: String? {
        guard let sizeEstimate else { return nil }
        let pixels = sizeEstimate.isClamped
            ? String(
                localized: "Will save at \(Self.count(sizeEstimate.width)) × \(Self.count(sizeEstimate.height))",
                comment: "Shown when a panorama is too wide for the JPEG format and has to come down"
            )
            : "\(Self.count(sizeEstimate.width)) × \(Self.count(sizeEstimate.height)) px"
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(sizeEstimate.bytes), countStyle: .file
        )
        if let shortfall = spaceShortfall {
            let more = ByteCountFormatter.string(fromByteCount: shortfall, countStyle: .file)
            return String(
                localized: "~\(size) — not enough free space (need \(more) more)",
                comment: "Panorama size estimate when the device is full"
            )
        }
        return "\(pixels) · \(Self.megapixels(sizeEstimate.megapixels)) MP · ~\(size) · ~\(Self.duration(sizeEstimate.seconds))"
    }

    private static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// Whole megapixels once there are enough of them to round without lying,
    /// one decimal below that — a small panorama reading "0 MP" says the tool
    /// produced nothing.
    private static func megapixels(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    /// Rounded the way a wait is spoken: seconds under a minute, then minutes
    /// and seconds. Never "0 s" — a save that fast still deserves a number.
    private static func duration(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        let allowed: Set<Duration.UnitsFormatStyle.Unit> =
            total < 60 ? [.seconds] : [.minutes, .seconds]
        return Duration.seconds(total).formatted(.units(allowed: allowed, width: .narrow))
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
        guard registration.solution.cameras.count >= 2 else {
            state = .noOverlap
            return
        }
        workingImages = images
        allSources = sources
        // Registration ran on the luminance image; the preview frames are the
        // proxy's own size, so the focal length comes back up with them.
        previewScale = Double(pixelWidth) / Double(images[0].width)
        previewWidth = pixelWidth
        previewHeight = pixelHeight
        adopt(solution: registration.solution, pairs: registration.pairs)

        state = .stitching(String(localized: "Blending…"))
        await renderPreview(quality: .draft)
        state = .ready
        schedulePreview(immediate: false)
    }

    /// Takes a solution as the one the screen is showing: which frames are in,
    /// what each one's exposure has to be corrected by, and which projections
    /// that geometry can still be built with. Run once when the panorama is
    /// first solved, and again after every Arrange.
    private func adopt(solution: PanoramaCameraSolution, pairs: [PanoramaPairObservation]) {
        self.solution = solution
        self.pairs = pairs
        cameras = solution.cameras
        unplaced = solution.unplaced
        previewFocal = solution.focal * previewScale

        let gains = PanoramaGainSolver.gains(
            frameCount: workingImages.count,
            overlaps: PanoramaGainMeasurement.overlaps(pairs: pairs, images: workingImages)
        )
        previewSources = solution.cameras.keys.sorted().compactMap { index in
            guard index < allSources.count, let camera = solution.cameras[index] else { return nil }
            var source = allSources[index]
            source.camera = camera
            source.gain = index < gains.count ? gains[index] : 1
            return source
        }

        availability = PanoramaProjection.availability(
            cameras: previewSources.map(\.camera),
            focal: previewFocal,
            imageWidth: previewWidth,
            imageHeight: previewHeight
        )
        if availability.first(where: { $0.kind == projection })?.isAvailable != true,
           let fallback = availability.first(where: \.isAvailable) {
            projection = fallback.kind
        }
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
        let warp = boundaryWarp
        let context = context

        let started = ContinuousClock.now
        let rendered: Render? = await Task.detached(priority: .userInitiated) {
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
            case .draft:
                image = PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)
            case .sharp:
                // The sharp tier is where the joins are found, so the preview
                // makes the same decision the saved photo will about anyone
                // who walked through the overlap (FS-14.02 §5).
                let seams = PanoramaSeamPlanner.masks(
                    canvas: canvas, sources: sources, focal: focal, context: context
                )
                image = PanoramaCIBlender.sharp(
                    canvas: canvas, sources: sources, focal: focal, seamMasks: seams
                )
            }
            guard var image else { return nil }

            let coverage = (cropping || warp > 0)
                ? Self.coverage(for: image, canvas: canvas, context: context)
                : nil

            // The warp comes before the crop: it is what makes the crop small,
            // and cropping first would throw away the very edge it pulls on.
            if warp > 0, let coverage,
               let mesh = PanoramaBoundaryWarp.mesh(
                   coverage: coverage, width: canvas.width, height: canvas.height, strength: warp
               ),
               let warped = PanoramaBoundaryWarp.apply(
                   mesh, to: image, width: canvas.width, height: canvas.height
               ) {
                image = warped
            }

            var region = PanoramaCropRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
            if cropping, let coverage, warp < 1,
               let crop = Self.cropRect(for: coverage, canvas: canvas) {
                region = crop
            }
            // Core Image counts from the bottom; the crop, like everything
            // else that indexes rows, counts from the top.
            let extent = CGRect(
                x: region.x,
                y: canvas.height - region.y - region.height,
                width: region.width,
                height: region.height
            )
            guard let cgImage = context.createCGImage(image, from: extent) else { return nil }
            // The size the photo would be saved at: the full-resolution canvas
            // with the same crop taken off it. Measured here rather than
            // guessed, because the crop is read off the coverage and only this
            // render knows it.
            let fraction = (
                width: Double(extent.width) / Double(canvas.width),
                height: Double(extent.height) / Double(canvas.height)
            )
            return Render(
                image: cgImage,
                fullWidth: Int((Double(full.width) * fraction.width).rounded()),
                fullHeight: Int((Double(full.height) * fraction.height).rounded()),
                canvasWidth: full.width,
                canvasHeight: full.height,
                canvas: canvas,
                crop: region
            )
        }.value

        guard !Task.isCancelled, let rendered else { return }
        preview = rendered.image
        fullOutputWidth = rendered.fullWidth
        fullOutputHeight = rendered.fullHeight
        fullCanvasWidth = rendered.canvasWidth
        fullCanvasHeight = rendered.canvasHeight
        previewCanvas = rendered.canvas
        previewCrop = rendered.crop
        if quality == .sharp {
            // Only the sharp tier is the work Save does, so only it can say
            // how long Save will take. The draft is a different renderer.
            let elapsed = started.duration(to: .now)
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) * 1e-18
            let megapixels = Double(rendered.image.width) * Double(rendered.image.height) / 1_000_000
            if megapixels > 0 {
                secondsPerMegapixel = seconds / megapixels
            }
            measureBytesPerPixel(of: rendered.image)
        }
    }

    /// What a pixel of this picture costs as JPEG, taken by compressing the
    /// preview at the quality the save uses — the Resize screen's method, and
    /// the only one that accounts for how busy this particular picture is.
    private func measureBytesPerPixel(of image: CGImage) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: PanoramaExporter.jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return }
        let pixels = Double(image.width) * Double(image.height)
        guard pixels > 0 else { return }
        bytesPerPixel = Double(data.length) / pixels
    }

    /// One render's product: the picture, how big that picture would be at the
    /// frames' own resolution, and the geometry the stage needs to turn a
    /// point under a finger into a direction in the panorama.
    private struct Render: @unchecked Sendable {
        let image: CGImage
        let fullWidth: Int
        let fullHeight: Int
        let canvasWidth: Int
        let canvasHeight: Int
        let canvas: PanoramaCanvas
        let crop: PanoramaCropRect
    }

    /// The Auto Crop rectangle, read off the preview's own coverage.
    private nonisolated static func cropRect(
        for coverage: [Float],
        canvas: PanoramaCanvas
    ) -> PanoramaCropRect? {
        PanoramaAutoCrop.largestRectangle(
            coverage: coverage, width: canvas.width, height: canvas.height
        )
    }

    /// Where the panorama has picture, one value per canvas pixel. Read once
    /// and used twice — Boundary Warp needs to know where the edge is, and so
    /// does Auto Crop.
    private nonisolated static func coverage(
        for image: CIImage,
        canvas: PanoramaCanvas,
        context: CIContext
    ) -> [Float]? {
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
        return coverage
    }


    // MARK: Arranging (FS-14.01 §5)

    /// One frame as Arrange shows it: where its outline sits on the stage and
    /// whether it is in the picture at all.
    struct ArrangedFrame: Identifiable, Equatable {
        let id: Int
        /// The frame's four corners in the preview image's own unit square,
        /// clockwise from the top left. Empty for a frame that is not placed.
        var outline: [CGPoint]
        var isPlaced: Bool

        /// "Photo 3 of 10, placed" — what VoiceOver reads for the outline.
        func accessibilityLabel(of total: Int) -> String {
            isPlaced
                ? String(localized: "Photo \(id + 1) of \(total), placed")
                : String(localized: "Photo \(id + 1) of \(total), not placed")
        }
    }

    /// Whether the stage is showing frame outlines and taking drags.
    private(set) var isArranging = false
    /// Why the last drag did not take. Cleared by the next one.
    private(set) var arrangeMessage: String?
    /// True while a drop is being matched, which takes long enough to say so.
    private(set) var isArrangingFrame = false
    private var arrangeTask: Task<Void, Never>?

    /// Arrange is only worth entering once there is a picture to correct.
    var canArrange: Bool { hasPicture && !isSaving }

    func toggleArrange() {
        guard canArrange else { return }
        isArranging.toggle()
        arrangeMessage = nil
    }

    /// A small colour picture of one frame, for the Not Placed strip. Taken
    /// from the proxy the stitch already loaded, so it costs no PhotoKit round
    /// trip and shows the frame as the panorama sees it.
    func thumbnail(for frame: Int) -> CGImage? {
        if let cached = thumbnails[frame] { return cached }
        guard frame < allSources.count else { return nil }
        let source = allSources[frame]
        let edge = 96.0
        let scale = edge / Double(max(source.width, source.height, 1))
        let scaled = source.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        thumbnails[frame] = image
        return image
    }

    /// Every frame, placed or not, with the outline the stage draws.
    var arrangedFrames: [ArrangedFrame] {
        (0..<assets.count).map { index in
            ArrangedFrame(
                id: index,
                outline: outline(of: index) ?? [],
                isPlaced: cameras[index] != nil
            )
        }
    }

    /// The frame's corners projected onto the preview, in unit coordinates of
    /// the image as it is displayed — which is what a SwiftUI overlay can
    /// scale into place without knowing anything about panoramas.
    private func outline(of frame: Int) -> [CGPoint]? {
        guard let camera = cameras[frame], let canvas = previewCanvas, let crop = previewCrop,
              crop.width > 0, crop.height > 0, previewFocal > 0
        else { return nil }
        let width = Double(previewWidth), height = Double(previewHeight)
        let corners = [(0.0, 0.0), (width, 0.0), (width, height), (0.0, height)]
        var points: [CGPoint] = []
        let inverse = PanoramaRotation.transposed(camera.rotation)
        for corner in corners {
            let ray = (
                (corner.0 - width / 2) / previewFocal,
                (corner.1 - height / 2) / previewFocal,
                1.0
            )
            let length = (ray.0 * ray.0 + ray.1 * ray.1 + ray.2 * ray.2).squareRoot()
            let direction = PanoramaRotation.apply(
                inverse, to: (ray.0 / length, ray.1 / length, ray.2 / length)
            )
            guard let projected = canvas.project(direction) else { return nil }
            points.append(
                CGPoint(
                    x: (projected.x - Double(crop.x)) / Double(crop.width),
                    y: (projected.y - Double(crop.y)) / Double(crop.height)
                )
            )
        }
        return points
    }

    /// Puts `frame` where the finger let go — `point` is in the preview
    /// image's unit square.
    ///
    /// The drop is a hint, not an answer: the frame still has to match what it
    /// landed among, and when it cannot the picture is left exactly as it was
    /// and the screen says so.
    func place(frame: Int, at point: CGPoint) {
        guard let canvas = previewCanvas, let crop = previewCrop, let solution else { return }
        let canvasX = Double(crop.x) + Double(crop.width) * point.x
        let canvasY = Double(crop.y) + Double(crop.height) * point.y
        guard let direction = canvas.direction(atX: canvasX, y: canvasY) else { return }

        arrangeMessage = nil
        arrangeTask?.cancel()
        isArrangingFrame = true
        let images = workingImages
        let pairs = pairs
        arrangeTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                try? PanoramaArranger.place(
                    frame: frame,
                    towards: direction,
                    images: images,
                    pairs: pairs,
                    solution: solution
                )
            }.value
            guard let self, !Task.isCancelled else { return }
            isArrangingFrame = false
            guard let outcome else {
                arrangeMessage = String(
                    localized: "That photo doesn't match what's there. Try dropping it where it overlaps.",
                    comment: "Panorama Arrange: the dropped frame could not be matched"
                )
                return
            }
            adopt(solution: outcome.solution, pairs: outcome.pairs)
            schedulePreview(immediate: true)
        }
    }

    /// Takes a frame out of the picture — the drag into Not Placed.
    func removeFromPanorama(frame: Int) {
        guard let solution, cameras[frame] != nil else { return }
        arrangeMessage = nil
        guard let outcome = try? PanoramaArranger.remove(
            frame: frame, images: workingImages, pairs: pairs, solution: solution
        ) else {
            arrangeMessage = String(
                localized: "A panorama needs at least two photos.",
                comment: "Panorama Arrange: refusing to remove the second-to-last frame"
            )
            return
        }
        adopt(solution: outcome.solution, pairs: outcome.pairs)
        schedulePreview(immediate: true)
    }

    // MARK: Saving

    func save() {
        guard canSave else { return }
        isCancelledFlag.withLock { $0 = false }
        saveProgress = 0
        let options = PanoramaStitchOptions(
            projection: projection,
            sizeScale: sizeScale,
            autoCrop: autoCrop,
            boundaryWarp: boundaryWarp
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
