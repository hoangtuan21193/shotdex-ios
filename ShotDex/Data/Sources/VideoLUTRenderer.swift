import CoreImage
import Foundation
import ShotDexKit

/// The parsed tables, kept so the compositor does not re-read a text file
/// thirty times a second.
///
/// `@unchecked Sendable` behind a lock, like `FilmLookTableCache`: the
/// compositor runs on AVFoundation's own queue, the panel asks from the main
/// actor, and both want the same table.
final class VideoLUTTableCache: @unchecked Sendable {
    static let shared = VideoLUTTableCache()

    private let lock = NSLock()
    private var tables: [String: CubeLUT] = [:]
    private var order: [String] = []
    /// A 33³ table is 575 KB and a 64³ one is 4 MB. Four is enough for a
    /// project plus whatever the user is auditioning.
    private let capacity = 4

    /// The table for `id`, loading and parsing it from `url` on a miss.
    /// Returns nil when the file is gone or does not parse — a deleted LUT
    /// degrades to no LUT.
    func table(id: String, url: URL) -> CubeLUT? {
        lock.lock()
        if let cached = tables[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? CubeLUTParser.parse(text)
        else { return nil }

        lock.lock()
        tables[id] = parsed
        order.append(id)
        while order.count > capacity {
            tables.removeValue(forKey: order.removeFirst())
        }
        lock.unlock()
        return parsed
    }

    func forget(_ id: String) {
        lock.lock()
        tables.removeValue(forKey: id)
        order.removeAll { $0 == id }
        lock.unlock()
    }
}

/// Applies an imported `.cube` LUT to a frame.
///
/// One `CIColorCubeWithColorSpace` pass in sRGB, for the same reason the
/// film looks take that path: a `.cube` is authored against gamma-encoded
/// code values, not against light, so running it in the context's linear
/// working space would apply the right table to the wrong numbers.
enum VideoLUTRenderer {
    /// `image` graded through `lut` at its intensity, or `image` unchanged
    /// when the table is missing or the intensity is zero.
    static func apply(
        _ reference: VideoLUTReference?,
        url: URL?,
        to image: CIImage
    ) -> CIImage {
        guard let reference, let url, reference.intensity > 0.001,
              let lut = VideoLUTTableCache.shared.table(id: reference.id, url: url),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return image }

        // A cube says nothing about values outside 0…1, and exposure or a
        // de-log pass can easily leave them there.
        let clamped = PhotoRenderService.filtered("CIColorClamp", image: image)
        let graded = PhotoRenderService.filtered(
            "CIColorCubeWithColorSpace",
            image: clamped,
            values: [
                "inputCubeDimension": lut.dimension,
                "inputCubeData": lut.data,
                "inputColorSpace": space,
            ]
        ).cropped(to: image.extent)

        guard reference.intensity < 0.999 else { return graded }
        // Partial strength is the graded frame laid over the original at
        // that alpha — the same mix `applyFilter(_:intensity:)` does, and
        // the way a look pack is meant to be used.
        let faded = PhotoRenderService.filtered(
            "CIColorMatrix",
            image: graded,
            values: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: reference.intensity)]
        )
        return faded.composited(over: image).cropped(to: image.extent)
    }
}
