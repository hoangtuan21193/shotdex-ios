import Foundation

/// The maker's lens data per file, read once (FS-03.16a §1): a render must
/// not re-read the RAW's bytes every frame. Bounded; a miss that found
/// nothing is remembered too.
public final class EmbeddedLensDataCache: @unchecked Sendable {
    public static let shared = EmbeddedLensDataCache()

    private let lock = NSLock()
    private var entries: [String: EmbeddedLensCorrection?] = [:]
    private var order: [String] = []
    private static let capacity = 16

    public init() {}

    /// Puts a correction in for `url` — tests, and a reader run elsewhere.
    public func store(_ correction: EmbeddedLensCorrection?, for url: URL) {
        lock.lock()
        entries[url.path] = .some(correction)
        order.append(url.path)
        lock.unlock()
    }

    public func correction(for url: URL) -> EmbeddedLensCorrection? {
        let key = url.path
        lock.lock()
        if let cached = entries[key] { lock.unlock(); return cached }
        lock.unlock()
        let read = EmbeddedLensDataReader.read(url: url)
        lock.lock()
        entries[key] = .some(read)
        order.append(key)
        if order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
        lock.unlock()
        return read
    }
}
