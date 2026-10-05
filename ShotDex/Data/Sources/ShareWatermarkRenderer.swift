import CoreGraphics
import Foundation
import ImageIO
import ShotDexKit
import UniformTypeIdentifiers

/// What a share stamps (FS-05.04 §4–5), decided before the share sheet opens:
/// the preset with its placement, each photo's token values, and the photos
/// whose saved edit already carries a layer from the preset. A value, so it
/// travels into the pipeline, the lazy batch and a drag alike.
struct ShareWatermark: Sendable, Equatable {
    /// The preset and the forms' remembered placement, tokens unfilled.
    let template: WatermarkStamp
    /// Token values by source id; a source without an entry has none.
    var tokens: [String: OverlayTokenValues] = [:]
    /// Source ids whose edit already has a layer pasted from this preset.
    var alreadyStamped: Set<String> = []

    var name: String { template.name }

    /// The stamp for one photo by id, or nil when its edit already carries
    /// the preset or every token is empty.
    func stamp(forID id: String) -> WatermarkStamp? {
        guard !alreadyStamped.contains(id),
              case .stamp(let stamp) = WatermarkPlan.decide(template, values: tokens[id] ?? .empty)
        else { return nil }
        return stamp
    }

    /// What happens to one source.
    func decision(for source: ShareSource) -> ShareWatermarkDecision {
        guard source.kind != .video else { return .video }
        if alreadyStamped.contains(source.id) { return .alreadyStamped }
        switch WatermarkPlan.decide(template, values: tokens[source.id] ?? .empty) {
        case .stamp(let stamp): return .stamp(stamp)
        case .nothingToStamp: return .nothingToStamp
        }
    }
}

/// Export to Files' stamp step (FS-03.07b seam, FS-05.04 §4): the photo's
/// stamp rides on the render and `write` composites it inside its box.
struct WatermarkExportStamping: ExportStamping {
    let watermark: ShareWatermark

    func stamp(_ result: PhotoRenderResult, for item: FileExportItem) async throws -> PhotoRenderResult {
        guard let stamp = watermark.stamp(forID: item.id) else { return result }
        var stamped = result
        stamped.watermark = stamp
        return stamped
    }
}

enum ShareWatermarkDecision: Equatable, Sendable {
    case stamp(WatermarkStamp)
    /// Its edit already has the preset: it goes as it is.
    case alreadyStamped
    /// Every token came out empty: nothing to stamp, named in the summary.
    case nothingToStamp
    /// Videos are never stamped (FS-05.04 §2).
    case video
}

/// A shared photo with a watermark (FS-05.04 §5): decoded upright, stamped
/// at full size, encoded again, then given the source's metadata at the
/// share's level — "render, then metadata". The rule that All Metadata hands
/// the bytes over as they are cannot hold for a stamped file.
enum ShareWatermarkRenderer {
    enum Failure: Error, Equatable {
        /// iOS cannot decode the file — a RAW from a camera newer than the
        /// system (FS-03.04b). It is left out and named, never sent unstamped.
        case unreadable
        case cannotWrite
    }

    /// JPEG and HEIC quality of a stamped share.
    static let quality = 0.95

    /// The type a stamped file is written in: the source's for JPEG, HEIC,
    /// PNG and TIFF; JPEG for a RAW, for anything else, and for a HEIC at No
    /// Metadata (FS-08.06 §3).
    static func outputType(sourceType: String?, level: MetadataLevel) -> UTType {
        guard let sourceType, let type = UTType(sourceType) else { return .jpeg }
        if type.conforms(to: .rawImage) { return .jpeg }
        if type.conforms(to: .heic) || type.conforms(to: .heif) {
            return level == .noMetadata || !supportsHEIC ? .jpeg : .heic
        }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .tiff) { return .tiff }
        return .jpeg
    }

    static var supportsHEIC: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)
    }

    /// The file name a stamped copy gets: the source's, with the output
    /// type's extension when it changed.
    static func outputName(for filename: String, type: UTType) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.lowercased()
        let keeps = switch type {
        case .jpeg: ["jpg", "jpeg"].contains(ext)
        case .heic: ["heic", "heif"].contains(ext)
        case .png: ext == "png"
        case .tiff: ["tif", "tiff"].contains(ext)
        default: false
        }
        return keeps ? filename : base + "." + (type == .jpeg ? "jpg" : type.preferredFilenameExtension ?? "jpg")
    }

    /// Writes `original` stamped to `destination`, in `type`.
    static func render(
        _ original: URL,
        stamp: WatermarkStamp,
        type: UTType,
        level: MetadataLevel,
        to destination: URL,
        renderer: PhotoRenderService = PhotoRenderService()
    ) async throws {
        let info: PhotoRenderSourceInfo
        let rendered: PhotoRenderResult
        do {
            info = try await renderer.inspectSource(at: original)
            rendered = try await renderer.render(source: info, recipe: .identity)
        } catch {
            throw Failure.unreadable
        }
        let stamped = await renderer.applyingWatermark(stamp, to: rendered)
        let pixels: CGImage
        do {
            pixels = try await renderer.encodablePixels(stamped)
        } catch {
            throw Failure.cannotWrite
        }
        let plain = destination.deletingLastPathComponent()
            .appendingPathComponent("stamped-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "jpg")")
        defer { try? FileManager.default.removeItem(at: plain) }
        guard let output = CGImageDestinationCreateWithURL(plain as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.cannotWrite }
        var options: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if type == .jpeg || type == .heic {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(output, pixels, options as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw Failure.cannotWrite }
        // The pixels are upright and SDR: orientation 1, no gain map tags.
        try MetadataRewriter.rewrite(plain, metadataFrom: original, to: destination, level: level, droppingGainMap: true)
    }
}
