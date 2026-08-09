import Foundation
import ImageIO
import UniformTypeIdentifiers

/// On-disk cache of the images used by signature layers.
///
/// A picked signature is copied here rather than referenced in the photo library:
/// the renderer needs its bytes for every frame it draws, the recipe only carries
/// the identifier, and a signature has to keep working after the photo it came
/// from is deleted.
///
/// Nothing is pruned automatically. A recipe lives inside a photo's
/// `PHAdjustmentData` and can outlive the preset that created it, so an id no
/// preset mentions is not evidence the file is unused. Files are a few kilobytes;
/// a wrong deletion loses a watermark.
struct OverlayImageStore: Sendable {
    let directory: URL

    /// Answers to `imageExists`, because the Text panel asks once per layer per
    /// frame — a filesystem stat per frame on the main thread is exactly the kind of
    /// work that turns a drag into a slideshow. Accurate because files only appear
    /// through `store` and only vanish through `remove`.
    private final class ExistenceCache: @unchecked Sendable {
        static let shared = ExistenceCache()
        private let lock = NSLock()
        private var known: [URL: Bool] = [:]

        func exists(at url: URL) -> Bool {
            lock.lock()
            if let cached = known[url] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let exists = FileManager.default.fileExists(atPath: url.path)
            lock.lock()
            known[url] = exists
            lock.unlock()
            return exists
        }

        func set(_ exists: Bool, at url: URL) {
            lock.lock()
            known[url] = exists
            lock.unlock()
        }
    }

    /// Alongside the database, in the directory that is backed up and not purged
    /// under storage pressure — the same reasoning as `AppDatabase.makeShared()`.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.temporaryDirectory
        return base.appendingPathComponent("Watermarks", isDirectory: true)
    }

    init(directory: URL = OverlayImageStore.defaultDirectory()) {
        self.directory = directory
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png", isDirectory: false)
    }

    func imageExists(id: UUID) -> Bool {
        ExistenceCache.shared.exists(at: url(for: id))
    }

    /// Stores PNG bytes under a fresh identifier. PNG rather than the source
    /// format because a signature without its alpha channel is a white box.
    @discardableResult
    func store(pngData: Data, id: UUID = UUID()) throws -> UUID {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let destination = url(for: id)
        try pngData.write(to: destination, options: .atomic)
        ExistenceCache.shared.set(true, at: destination)
        return id
    }

    func remove(id: UUID) {
        let target = url(for: id)
        try? FileManager.default.removeItem(at: target)
        ExistenceCache.shared.set(false, at: target)
    }

    /// Re-encodes arbitrary image data as PNG, keeping any alpha channel. Used for
    /// the rare library asset that is not already a PNG.
    static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
