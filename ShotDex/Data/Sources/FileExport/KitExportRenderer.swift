import Foundation
import ImageIO
import ShotDexKit
import UniformTypeIdentifiers

/// Current Version through the kit's renderer, as Resize renders
/// (FS-03.07 §3–4): the source as it is (`.identity` — an edit made in
/// Photos is already in the file), once, at the preset, Fill cropped from
/// the centre; then the stamp; then written with the **source's** metadata
/// at the level, so a stamp never changes what the file says about itself.
struct KitExportRenderer: ExportRendering {
    let renderer: PhotoRenderService

    init(renderer: PhotoRenderService = PhotoRenderService()) {
        self.renderer = renderer
    }

    func inspect(_ url: URL) async throws -> PhotoRenderSourceInfo {
        try await renderer.inspectSource(at: url)
    }

    func render(
        _ source: PhotoRenderSourceInfo,
        options: FileExportRenderOptions,
        stamp: (any ExportStamping)?,
        item: FileExportItem,
        to url: URL
    ) async throws {
        var result = try await renderer.render(source: source, recipe: .identity)
        if options.preset.kind != .original {
            result = await renderer.resize(result, preset: options.preset, cropAnchor: .center)
        }
        if let stamp {
            do {
                result = try await stamp.stamp(result, for: item)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FileExportFailure.stampFailed
            }
        }
        try Task.checkCancellation()
        try await renderer.write(result, to: url, format: options.format, quality: options.quality, metadata: options.metadata)
    }

    /// The format a photo is written in: JPEG or HEIC as asked; Same as
    /// Original keeps HEIC as HEIC and turns everything else — RAW, PNG,
    /// TIFF, JPEG — into JPEG (FS-03.07b §3). HEIC where the device can't
    /// encode it is JPEG.
    static func format(for item: FileExportItem, requested: PhotoOutputFormat) -> PhotoOutputFormat {
        let resolved: PhotoOutputFormat
        switch requested {
        case .jpeg, .heic: resolved = requested
        case .preserve:
            resolved = ["heic", "heif"].contains((item.filename as NSString).pathExtension.lowercased()) ? .heic : .jpeg
        }
        return resolved == .heic && !supportsHEICEncoding ? .jpeg : resolved
    }

    /// Whether ImageIO here writes HEIC (the simulator on some Macs does not).
    static var supportsHEICEncoding: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)
    }
}
