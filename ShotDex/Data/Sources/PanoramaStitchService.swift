import CoreImage
import Foundation
import Photos
import ShotDexKit

/// What the user chose on the panorama screen.
struct PanoramaStitchOptions: Sendable {
    var projection: PanoramaProjectionKind = .spherical
    /// The Size control, 0.25…1 of the frames' own resolution.
    var sizeScale: Double = 1
    var autoCrop = true

    init(projection: PanoramaProjectionKind = .spherical, sizeScale: Double = 1, autoCrop: Bool = true) {
        self.projection = projection
        self.sizeScale = sizeScale
        self.autoCrop = autoCrop
    }
}

/// Where a stitch has got to, for the screen to say out loud.
enum PanoramaStitchPhase: Sendable, Equatable {
    case loading(done: Int, total: Int)
    case findingOverlaps
    case aligning
    case blending
    case writing(fraction: Double)
    case saving
}

enum PanoramaStitchError: Error, Equatable {
    case needsTwoImages
    /// Frames that are only in iCloud and would not come down. Carries how
    /// many, because the screen says the number (FS-14.01 §2).
    case framesUnavailable(count: Int)
    case noOverlappingFrames
    case projectionUnavailable
    case cancelled
    case renderFailed
}

/// One frame, ready for both halves of the job.
struct PanoramaStitchFrame {
    /// Full resolution, for the picture that gets saved.
    var image: CIImage
    var width: Int
    var height: Int
    /// Downscaled luminance, for finding the overlaps. Registration never looks
    /// at a full-resolution frame.
    var working: PanoramaImage
    /// The frame's own image properties, for the metadata rule.
    var properties: [CFString: Any]
}

/// Turns a run of selected photos into one saved panorama.
///
/// Glue, deliberately: every decision it makes lives somewhere testable in
/// `ShotDexKit`, and what is left here is the order of the steps and the
/// places the work can be cancelled or fail. The frame loader is injected so
/// the whole chain can be exercised without a photo library.
struct PanoramaStitchService {
    /// Loads one frame. Nil means the frame could not be obtained — almost
    /// always an iCloud original that would not come down.
    var loadFrame: @Sendable (PHAsset) async -> PanoramaStitchFrame?
    /// Creates the asset from the file on disk.
    var saveFile: @Sendable (URL, String) async throws -> String
    /// Indexes the new asset immediately, so the viewer that opens onto it
    /// already knows it is a panorama.
    var indexAsset: @Sendable (String) async -> Void

    /// The long edge registration works at.
    static let workingEdge = PanoramaImage.workingEdge

    func stitch(
        assets: [PHAsset],
        options: PanoramaStitchOptions = PanoramaStitchOptions(),
        progress: @escaping @Sendable (PanoramaStitchPhase) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async throws -> String {
        let photos = assets.filter { $0.mediaType == .image }
        guard photos.count >= 2 else { throw PanoramaStitchError.needsTwoImages }

        // 1. Every frame, once. Both resolutions come out of the same read:
        // asking PhotoKit twice for the same original is the expensive mistake
        // available here.
        var frames: [PanoramaStitchFrame] = []
        var missing = 0
        for (index, asset) in photos.enumerated() {
            if isCancelled() { throw PanoramaStitchError.cancelled }
            progress(.loading(done: index, total: photos.count))
            if let frame = await loadFrame(asset) {
                frames.append(frame)
            } else {
                missing += 1
            }
        }
        guard missing == 0 else { throw PanoramaStitchError.framesUnavailable(count: missing) }
        guard frames.count >= 2 else { throw PanoramaStitchError.needsTwoImages }

        // 2. Which frames belong together, and where each was pointing.
        if isCancelled() { throw PanoramaStitchError.cancelled }
        progress(.findingOverlaps)
        let registration: PanoramaRegistration
        do {
            registration = try PanoramaRegistrar.register(
                images: frames.map(\.working),
                captureDates: photos.map(\.creationDate)
            )
        } catch PanoramaRegistrationError.needsTwoImages {
            throw PanoramaStitchError.needsTwoImages
        } catch {
            throw PanoramaStitchError.noOverlappingFrames
        }

        if isCancelled() { throw PanoramaStitchError.cancelled }
        progress(.aligning)
        let solution = registration.solution
        guard solution.cameras.count >= 2 else { throw PanoramaStitchError.noOverlappingFrames }

        // The solve works in the frames' own resolution; registration worked in
        // the downscaled one, so the focal length has to come back up with it.
        let scale = Double(frames[0].width) / Double(frames[0].working.width)
        let fullFocal = solution.focal * scale

        // 3. Exposure, matched across the seams.
        let gains = PanoramaGainSolver.gains(
            frameCount: frames.count,
            overlaps: PanoramaGainMeasurement.overlaps(
                pairs: registration.pairs, images: frames.map(\.working)
            )
        )

        // 4. The canvas. A projection the frames cannot support is refused
        // rather than drawn wrong — the screen dims it for the same reason.
        let placed = solution.cameras.keys.sorted()
        let cameras = placed.compactMap { solution.cameras[$0] }
        let availability = PanoramaProjection.availability(
            cameras: cameras, focal: fullFocal,
            imageWidth: frames[0].width, imageHeight: frames[0].height
        )
        guard availability.first(where: { $0.kind == options.projection })?.isAvailable == true else {
            throw PanoramaStitchError.projectionUnavailable
        }
        guard let canvas = PanoramaProjection.canvas(
            kind: options.projection,
            cameras: cameras,
            focal: fullFocal,
            imageWidth: frames[0].width,
            imageHeight: frames[0].height,
            scale: options.sizeScale
        ) else { throw PanoramaStitchError.renderFailed }

        let sources = placed.enumerated().compactMap { position, frameIndex -> PanoramaCISource? in
            guard frameIndex < frames.count, let camera = solution.cameras[frameIndex] else { return nil }
            _ = position
            return PanoramaCISource(
                image: frames[frameIndex].image,
                width: frames[frameIndex].width,
                height: frames[frameIndex].height,
                camera: camera,
                gain: frameIndex < gains.count ? gains[frameIndex] : 1
            )
        }
        guard !sources.isEmpty else { throw PanoramaStitchError.renderFailed }

        if isCancelled() { throw PanoramaStitchError.cancelled }
        progress(.blending)
        let crop = options.autoCrop
            ? PanoramaAutoCrop.largestRectangle(
                coverage: coverage(canvas: canvas, sources: sources, focal: fullFocal),
                width: canvas.width,
                height: canvas.height
            )
            : nil

        // 5. Out to a file, a strip at a time.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPano-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let region = crop ?? PanoramaCropRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let filename = "panorama-\(region.width)x\(region.height).jpg"
        let url = directory.appendingPathComponent(filename)
        let properties = PanoramaMetadataRule.merge(
            frames: placed.compactMap { $0 < frames.count ? frames[$0].properties : nil },
            pixelWidth: region.width,
            pixelHeight: region.height
        )
        let metadata = PanoramaXMP.makeMetadata(
            projection: options.projection.rawValue, frameCount: sources.count
        )

        do {
            try PanoramaExporter.write(
                canvas: canvas,
                sources: sources,
                focal: fullFocal,
                quality: .sharp,
                crop: crop,
                to: url,
                properties: properties,
                metadata: metadata,
                progress: { progress(.writing(fraction: $0)) },
                isCancelled: isCancelled
            )
        } catch PanoramaExportError.cancelled {
            throw PanoramaStitchError.cancelled
        } catch {
            throw PanoramaStitchError.renderFailed
        }

        // 6. Into the library, then straight into the index — the viewer that
        // opens onto it has to already know it is a panorama.
        if isCancelled() { throw PanoramaStitchError.cancelled }
        progress(.saving)
        let identifier = try await saveFile(url, filename)
        await indexAsset(identifier)
        return identifier
    }

    /// Where the panorama has pixels, read off a small draft rather than the
    /// full-size render: Auto Crop needs the shape, not the picture, and the
    /// shape is the same at any scale.
    private func coverage(
        canvas: PanoramaCanvas,
        sources: [PanoramaCISource],
        focal: Double
    ) -> [Float] {
        let width = canvas.width, height = canvas.height
        guard let draft = PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal) else {
            return [Float](repeating: 1, count: width * height)
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            context.render(
                draft,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        var coverage = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let sourceRow = (height - 1 - y) * width
            for x in 0..<width {
                coverage[y * width + x] = rgba[4 * (sourceRow + x) + 3] > 0 ? 1 : 0
            }
        }
        return coverage
    }
}

extension PanoramaStitchService {
    /// The service as the app runs it.
    ///
    /// The loader is the only part that touches PhotoKit, and it reads each
    /// original **once**: the full-resolution image for the picture, a
    /// downscaled luminance copy for finding the overlaps, and the properties
    /// for the metadata rule all come out of the same bytes.
    static func live(
        photoLibrary: PhotoLibraryService,
        indexAsset: @escaping @Sendable (String) async -> Void
    ) -> PanoramaStitchService {
        PanoramaStitchService(
            loadFrame: { asset in await frame(for: asset) },
            saveFile: { url, name in
                try await photoLibrary.saveImageFile(at: url, filename: name)
            },
            indexAsset: indexAsset
        )
    }

    private static func frame(for asset: PHAsset) async -> PanoramaStitchFrame? {
        guard let data = await originalData(for: asset) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let full = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions)
        else { return nil }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions)
            as? [CFString: Any]) ?? [:]
        guard let working = PanoramaImage.luminance(of: full) else { return nil }
        return PanoramaStitchFrame(
            image: CIImage(cgImage: full),
            width: full.width,
            height: full.height,
            working: working,
            properties: properties
        )
    }

    /// The original's bytes. Network allowed, because a frame that lives only
    /// in iCloud is still one the photographer selected — and when it cannot be
    /// fetched the caller counts it rather than leaving it out.
    private static func originalData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
