import CoreImage
import Foundation
import ShotDexKit

/// The baked look tables (FS-12.06c §5), shared by the preview, the export
/// and the scopes.
///
/// Counted in **tables**, not looks: a look with Clarity costs two. 24 of
/// them at 33³ float RGBA (≈575 KB each) is ≈14 MB — the ceiling §5 sets.
/// The least recently used one goes first. Keyed by what the table holds,
/// so two clips with the same look share one, and a My Look taken again
/// after an edit in the photo editor bakes anew.
///
/// `@unchecked Sendable` behind a lock, like `LUTTableCache`: the compositor
/// reads on AVFoundation's queue, the model warms it from a detached task,
/// the scope from its own. A table never changes once baked.
final class VideoLookTableCache: @unchecked Sendable {
    static let shared = VideoLookTableCache()
    static let defaultCapacity = 24

    /// What one table holds: the slice of the look it bakes, encoded.
    struct Key: Hashable, Sendable {
        let content: Data

        init(_ part: VideoLookBaker.Part, of look: PhotoEditRecipe) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let slice = VideoLookBaker.recipe(part, of: look)
            content = (try? encoder.encode(slice)) ?? Data(part.rawValue.utf8)
        }
    }

    /// One baked table, its bytes made once: a fresh `Data` per frame
    /// cost 575 KB of copying each time.
    struct Table: Sendable {
        let dimension: Int
        let data: Data
    }

    let capacity: Int
    private let lock = NSLock()
    private var tables: [Key: Table] = [:]
    private var order: [Key] = []
    private let context = CIContext(options: [.cacheIntermediates: false, .name: "ShotDex Video Look Baker"])

    init(capacity: Int = VideoLookTableCache.defaultCapacity) {
        self.capacity = capacity
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return tables.count
    }

    func contains(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tables[key] != nil
    }

    /// The table for one part of `look`, baked now on a miss — on the
    /// compositor's queue that costs one frame its timing; the model warms
    /// the cache before it swaps a composition in (`prepare`), so it rarely
    /// happens.
    func table(_ part: VideoLookBaker.Part, of look: PhotoEditRecipe, key: Key? = nil) -> Table? {
        let key = key ?? Key(part, of: look)
        lock.lock()
        if let cached = tables[key] {
            order.removeAll { $0 == key }
            order.append(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let lut = VideoLookBaker.bake(part, of: look, context: context) else { return nil }
        let baked = Table(dimension: lut.dimension, data: lut.data)

        lock.lock()
        defer { lock.unlock() }
        if let raced = tables[key] { return raced }
        tables[key] = baked
        order.append(key)
        while order.count > capacity {
            tables.removeValue(forKey: order.removeFirst())
        }
        return baked
    }

    /// Bakes every table `looks` need, off the main actor, before the
    /// composition that reads them goes live (§5: bake when chosen).
    func prepare(_ looks: [PhotoEditRecipe]) async {
        let pending = looks
        await Task.detached(priority: .userInitiated) { [self] in
            for look in pending {
                for part in VideoLookBaker.parts(of: look) {
                    if Task.isCancelled { return }
                    _ = table(part, of: look)
                }
            }
        }.value
    }
}
