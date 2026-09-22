import CoreImage
import Foundation

/// Where imported `.cube` files live, from their id alone.
///
/// In the kit rather than the app's `ImportedLUTStore` because the photo
/// renderer resolves a recipe's LUT id while it renders, off the main actor,
/// and cannot ask a main-actor store. The store and the renderer agree on the
/// path instead.
public enum ImportedLUTFiles {
    public static func fileURL(for id: String) -> URL {
        directory().appendingPathComponent(id).appendingPathExtension("cube")
    }

    public static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ImportedLUTs", isDirectory: true)
    }

    /// The parsed table for `id`, or nil when the file is gone — a deleted
    /// LUT renders as no LUT, it does not fail the render.
    public static func table(for id: String) -> CubeLUT? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            LUTTableCache.shared.forget(id)
            return nil
        }
        return LUTTableCache.shared.table(id: id, url: url)
    }
}

/// The parsed tables, kept so the compositor does not re-read a text file
/// thirty times a second.
///
/// `@unchecked Sendable` behind a lock, like `FilmLookTableCache`: the
/// compositor runs on AVFoundation's own queue, the photo renderer on its
/// render queue, the panel asks from the main actor, and all want the same
/// table.
public final class LUTTableCache: @unchecked Sendable {
    public static let shared = LUTTableCache()

    private let lock = NSLock()
    private var tables: [String: CubeLUT] = [:]
    private var order: [String] = []
    /// A 33³ table is 575 KB and a 64³ one is 4 MB. Four is enough for a
    /// project plus whatever the user is auditioning.
    private let capacity = 4

    /// The table for `id`, loading and parsing it from `url` on a miss.
    /// Returns nil when the file is gone or does not parse — a deleted LUT
    /// degrades to no LUT.
    public func table(id: String, url: URL) -> CubeLUT? {
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

    public func forget(_ id: String) {
        lock.lock()
        tables.removeValue(forKey: id)
        order.removeAll { $0 == id }
        lock.unlock()
    }
}

extension PhotoRenderService {
    /// `image` graded through `lut` at `intensity`.
    ///
    /// One `CIColorCubeWithColorSpace` pass in sRGB, for the same reason the
    /// film looks take that path: a `.cube` is authored against gamma-encoded
    /// code values, not against light, so running it in the context's linear
    /// working space would apply the right table to the wrong numbers. Shared
    /// by the photo editor and Video Studio.
    public static func applyLUT(_ lut: CubeLUT, intensity: Double, to image: CIImage) -> CIImage {
        guard intensity > 0.001, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        // A cube says nothing about values outside 0…1, and exposure or a
        // de-log pass can easily leave them there.
        let clamped = filtered("CIColorClamp", image: image)
        let graded = filtered(
            "CIColorCubeWithColorSpace",
            image: clamped,
            values: [
                "inputCubeDimension": lut.dimension,
                "inputCubeData": lut.data,
                "inputColorSpace": space,
            ]
        ).cropped(to: image.extent)

        guard intensity < 0.999 else { return graded }
        // Partial strength is the graded frame laid over the original at
        // that alpha — the same mix `applyFilter(_:intensity:)` does, and
        // the way a look pack is meant to be used.
        let faded = filtered(
            "CIColorMatrix",
            image: graded,
            values: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: intensity)]
        )
        return faded.composited(over: image).cropped(to: image.extent)
    }
}
