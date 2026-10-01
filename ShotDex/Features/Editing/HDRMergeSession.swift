import CoreImage
import Foundation
import ImageIO
import os
import ShotDexKit
import UniformTypeIdentifiers

/// The HDR half of a Combine Photos screen (FS-01.11): the series' files on
/// this device, read once and kept for the save, the preview frames lined up
/// once, and the merge re-run from them for every Deghost or Strength change.
@MainActor
final class HDRMergeSession {
    private let folder: PhotoStackSession
    private let renderer: PhotoStackRenderer

    /// The frames' files, darkest first.
    private(set) var files: [HDRFrameFile] = []
    private(set) var order: HDRBracketOrder.Series<Int>?
    /// Preview frames, linear, in `files` order, rendered to memory once.
    private var previewFrames: [CIImage] = []
    /// Preview pixels per full-size pixel.
    private var previewScale = 1.0
    private(set) var prepared: PreparedHDR?
    private var radiance: (deghost: HDRDeghost, image: CIImage)?
    /// Frames decoded since the series was opened — what AC-9 counts.
    private(set) var frameReads = 0
    /// The darkest frame still clips over more than 1 % of the picture.
    private(set) var highlightsClipInEveryFrame = false

    init(renderer: PhotoStackRenderer) throws {
        folder = try PhotoStackSession()
        self.renderer = renderer
    }

    // MARK: Loading

    /// Fetches every photo's file, reads it small and linear, and puts the
    /// series in exposure order. Returns the photos that loaded, in that order.
    func load(_ photos: [PhotoEditOrigin]) async -> [PhotoEditOrigin] {
        prepared = nil
        radiance = nil
        var fetched: [(photo: PhotoEditOrigin, file: HDRFrameFile)] = []
        for (index, photo) in photos.enumerated() {
            guard let file = try? await HDRFrameSource.file(for: photo, in: folder.folder, index: index) else { continue }
            fetched.append((photo, file))
        }
        // RAW or processed for every frame alike (FS-01.11 §5).
        let fromRAW = !fetched.isEmpty && fetched.allSatisfy(\.file.isRAW)
        let fileList = fetched.map(\.file)
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodePreviews(fileList, fromRAW: fromRAW)
        }.value
        frameReads += decoded.frames.count
        let kept = decoded.frames.map { fetched[$0.index] }
        let series = HDRBracketOrder.series(kept.indices.map { index in
            kept[index].file.orderFrame(id: index, measuredLog2Brightness: decoded.frames[index].log2Median)
        })
        order = series
        files = series.order.map { kept[$0].file }
        previewFrames = series.order.map { decoded.frames[$0].image }
        previewScale = decoded.scale
        highlightsClipInEveryFrame = series.order.first.map { decoded.frames[$0].clipped > 0.01 } ?? false
        return series.order.map { kept[$0].photo }
    }

    struct DecodedPreview: @unchecked Sendable {
        var index: Int
        var image: CIImage
        var log2Median: Double?
        /// Share of pixels with a channel at the clip point.
        var clipped: Double
    }

    /// Reads every file small and linear and copies it into memory, so the
    /// preview never decodes it again: a RAW behind a live decoder would be
    /// re-read on every render. Off the main actor — a RAW takes a while.
    nonisolated static func decodePreviews(_ files: [HDRFrameFile], fromRAW: Bool)
        -> (frames: [DecodedPreview], scale: Double) {
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        var frames: [DecodedPreview] = []
        var scale = 1.0
        for (index, file) in files.enumerated() {
            guard let image = HDRFrameSource.linearImage(of: file, fromRAW: fromRAW, maxPixelSize: HDRFrameSource.previewEdge)
            else { continue }
            let extent = image.extent.integral
            guard extent.width > 0, extent.height > 0 else { continue }
            let width = Int(extent.width), height = Int(extent.height)
            var data = Data(count: width * height * 8)
            data.withUnsafeMutableBytes { bytes in
                context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 8, bounds: extent,
                               format: .RGBAh, colorSpace: nil)
            }
            let copy = CIImage(bitmapData: data, bytesPerRow: width * 8, size: extent.size, format: .RGBAh, colorSpace: nil)
            if frames.isEmpty { scale = HDRFrameSource.pixelScale(of: file, image: image) }
            frames.append(DecodedPreview(index: index, image: copy,
                                         log2Median: HDRFrameSource.medianLog2Luminance(of: copy, context: context),
                                         clipped: clippedFraction(copy, context: context)))
        }
        return (frames, scale)
    }

    nonisolated static func clippedFraction(_ frame: CIImage, context: CIContext) -> Double {
        let side = 128
        let small = frame.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / frame.extent.width,
                                                            y: CGFloat(side) / frame.extent.height))
        var pixels = [Float](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(small, toBitmap: bytes.baseAddress!, rowBytes: side * 16,
                           bounds: CGRect(origin: small.extent.origin, size: CGSize(width: side, height: side)),
                           format: .RGBAf, colorSpace: nil)
        }
        let clipped = (0..<(side * side)).filter { max(pixels[$0 * 4], pixels[$0 * 4 + 1], pixels[$0 * 4 + 2]) >= 0.98 }
        return Double(clipped.count) / Double(side * side)
    }

    // MARK: Preview

    /// The preview for `options`. The frames are lined up the first time
    /// only; Deghost re-merges, Strength only re-tone-maps.
    func render(_ options: HDROptions) async throws -> CGImage {
        guard let order, previewFrames.count >= CombinePurpose.minimumPhotoCount else {
            throw PhotoStackError.needsTwoImages
        }
        let ready: PreparedHDR
        if let prepared {
            ready = prepared
        } else {
            ready = try await renderer.prepareHDR(
                images: previewFrames, stops: order.stops, reference: order.reference,
                noise: order.mergesFromRAW ? .raw : .processed, pixelScale: previewScale)
            prepared = ready
        }
        let merged: CIImage
        if let radiance, radiance.deghost == options.deghost {
            merged = radiance.image
        } else {
            guard let image = HDRMerge.radiance(ready.series, deghost: options.deghost) else {
                throw PhotoStackError.renderFailed
            }
            merged = image
            radiance = (options.deghost, image)
        }
        guard let toned = HDRMerge.toneMapped(merged, stops: ready.series.stops, strength: options.strength) else {
            throw PhotoStackError.renderFailed
        }
        return try await renderer.render(toned)
    }

    // MARK: Notes

    /// The panel's warnings, in order (FS-01.11 §4, §5).
    var notes: [String] {
        var lines: [String] = []
        if let prepared, !prepared.excludedFrames.isEmpty {
            lines.append(String(
                localized: "\(prepared.excludedFrames.count) of \(files.count) frames couldn't be lined up and were left out.",
                comment: "Focus Stack panel: frames dropped because alignment failed. First number is dropped frames, second is all frames."
            ))
        }
        if order?.isSameExposure == true {
            lines.append(String(localized: "These photos have about the same exposure. HDR works best on a bracketed series.",
                                comment: "HDR panel: the selected photos are not an exposure bracket"))
        }
        if order?.isMixedRAW == true {
            lines.append(String(localized: "Some of these photos aren't RAW, so all of them are merged from their processed versions.",
                                comment: "HDR panel: a series mixing RAW and JPEG/HEIC is merged from the processed versions"))
        }
        if highlightsClipInEveryFrame {
            lines.append(String(localized: "Some highlights are bright in every frame and can't be recovered.",
                                comment: "HDR panel: even the darkest frame is clipped somewhere"))
        }
        return lines
    }

    // MARK: Save

    /// Writes the full-resolution merge to `url`, off the main actor.
    func save(options: HDROptions, type: UTType, to url: URL,
              progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let prepared, let order else { throw PhotoStackError.needsTwoImages }
        let files = self.files
        let fromRAW = order.mergesFromRAW
        let previewScale = self.previewScale
        let reference = files[prepared.inputIndices[prepared.series.reference]]
        let properties = Self.properties(of: reference)
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try HDRExporter.write(
                    frame: { HDRFrameSource.linearImage(of: files[$0], fromRAW: fromRAW, maxPixelSize: nil) },
                    prepared: prepared, previewScale: previewScale, options: options, type: type, to: url,
                    properties: properties, progress: progress,
                    isCancelled: { cancelled.withLock { $0 } }
                )
            }.value
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    /// The reference frame's metadata, less its exposure (AC-15).
    nonisolated static func properties(of file: HDRFrameFile) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        var result: [CFString: Any] = [:]
        for (key, value) in StackedPhotoMetadata.properties(fromReference: raw) { result[key as CFString] = value }
        return result
    }
}
