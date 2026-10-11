import Foundation

/// The bytes of a few server files read so far, so the thumbnail ladder,
/// the metadata read and the fast hash share one head read (FS-19.03 §2).
/// Nothing is read twice; nothing is read that a step did not ask for.
final class RemoteRangeReader: @unchecked Sendable {
    private struct Segment {
        let offset: Int64
        let data: Data
        var end: Int64 { offset + Int64(data.count) }
    }

    let client: any RemoteFileClient
    private var segments: [String: [Segment]] = [:]
    private let lock = NSLock()

    init(client: any RemoteFileClient) {
        self.client = client
    }

    /// Up to `length` bytes from `offset`, from what is held when one read
    /// already covered them, else from the server.
    func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
        if let held = held(path, offset: offset, length: length, fileLength: nil) { return held }
        let data = try await client.readRange(path, offset: offset, length: length)
        lock.withLock { segments[path, default: []].append(Segment(offset: offset, data: data)) }
        return data
    }

    /// What is held of `path`, as bytes a hasher can read. A read it cannot
    /// answer comes back as zeros and is noted in `misses`.
    func bytes(_ path: String, length: Int64) -> HeldBytes {
        HeldBytes(reader: self, path: path, length: length)
    }

    fileprivate func held(_ path: String, offset: Int64, length: Int, fileLength: Int64?) -> Data? {
        lock.withLock {
            let end = min(offset + Int64(length), fileLength ?? .max)
            for segment in segments[path] ?? [] where segment.offset <= offset && segment.end >= end {
                let start = segment.data.startIndex + Int(offset - segment.offset)
                return segment.data.subdata(in: start..<start + Int(end - offset))
            }
            return nil
        }
    }

    /// The fast hash of `path` (FS-19.02 §1) over ranges read on demand: the
    /// hasher runs on what is held, every range it lacked is fetched, and it
    /// runs again until it lacked nothing — the image-data layout of a TIFF
    /// is only known one IFD at a time.
    func fastHash(_ path: String, length: Int64) async throws -> ContentHash {
        for _ in 0..<32 {
            let view = bytes(path, length: length)
            let hash = try ContentHasher.hash(view, full: false)
            if view.misses.isEmpty { return hash }
            for miss in view.misses {
                _ = try await read(path, offset: miss.offset, length: miss.length)
            }
        }
        throw RemoteFileError.other("layout of \(path) never settled")
    }
}

/// A server file as far as `RemoteRangeReader` holds it.
final class HeldBytes: ContentBytes {
    /// Small reads are rounded up to this, so walking a header costs one
    /// round trip, not one per field.
    static let minimumRead = 4 * 1024

    private let reader: RemoteRangeReader
    private let path: String
    let length: Int64
    private(set) var misses: [(offset: Int64, length: Int)] = []

    fileprivate init(reader: RemoteRangeReader, path: String, length: Int64) {
        self.reader = reader
        self.path = path
        self.length = length
    }

    func read(offset: Int64, length wanted: Int) throws -> Data {
        guard offset < length else { return Data() }
        let count = Int(min(Int64(wanted), length - offset))
        if let held = reader.held(path, offset: offset, length: count, fileLength: length) { return held }
        misses.append((offset, Int(min(Int64(max(count, Self.minimumRead)), length - offset))))
        return Data(count: count)
    }
}
