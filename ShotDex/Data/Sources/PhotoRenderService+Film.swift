import CoreGraphics
import CoreImage
import Foundation

/// Built lookup tables, keyed by filter.
///
/// `applyFilter` and everything under it are `static` — the render graph is built
/// from free functions so the same code serves the editor, compression and bulk
/// export — so this cache cannot lean on actor isolation and carries its own lock.
/// Capped rather than unbounded, and sized to hold one whole strip: a table is
/// 575 KB, and the swatch grid asks for every look in the strip on screen. Holding
/// all of them means re-rendering the swatches after a slider settles reuses the
/// tables instead of rebuilding two dozen of them.
private final class FilmLookTableCache: @unchecked Sendable {
    static let shared = FilmLookTableCache()

    private static let capacity = 24
    private let lock = NSLock()
    private var tables: [String: Data] = [:]
    private var order: [String] = []

    func table(for look: FilmLook, key: String) -> Data {
        lock.lock()
        if let cached = tables[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Built outside the lock: a table takes a few milliseconds, and holding
        // the lock through it would stall every other render that wants a
        // different look. Two threads racing the same key just do it twice.
        let table = FilmLookLUT.data(for: look)

        lock.lock()
        if tables[key] == nil {
            tables[key] = table
            order.append(key)
            while order.count > Self.capacity {
                tables.removeValue(forKey: order.removeFirst())
            }
        }
        lock.unlock()
        return table
    }
}

extension PhotoRenderService {
    /// One `CIColorCube` pass for the whole look. The table is generated in display
    /// gamma, so the cube is told to work in sRGB rather than the context's linear
    /// working space — the curves in `FilmLook` were dialled against gamma-encoded
    /// values, which is what a film simulation in a camera operates on too.
    static func applyFilmLook(
        _ look: FilmLook,
        key: String,
        to input: CIImage
    ) -> CIImage {
        // A cube says nothing about values outside 0...1, and exposure or a RAW
        // base can easily leave them there.
        let clamped = filtered("CIColorClamp", image: input)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return clamped
        }
        return filtered(
            "CIColorCubeWithColorSpace",
            image: clamped,
            values: [
                "inputCubeDimension": FilmLookLUT.dimension,
                "inputCubeData": FilmLookTableCache.shared.table(for: look, key: key),
                "inputColorSpace": colorSpace,
            ]
        ).cropped(to: input.extent)
    }
}
