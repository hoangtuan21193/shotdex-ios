import CryptoKit
import Foundation

/// Bytes a hasher can read anywhere in: a file, a server range reader, or a
/// buffer streamed from Photos.
protocol ContentBytes {
    var length: Int64 { get }
    func read(offset: Int64, length: Int) throws -> Data
}

struct DataBytes: ContentBytes {
    let data: Data
    var length: Int64 { Int64(data.count) }
    func read(offset: Int64, length: Int) throws -> Data {
        let start = data.startIndex + Int(offset)
        let end = min(data.endIndex, start + length)
        guard start <= end else { return Data() }
        return data.subdata(in: start..<end)
    }
}

final class FileBytes: ContentBytes {
    private let handle: FileHandle
    let length: Int64

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        length = Int64(try handle.seekToEnd())
    }

    deinit { try? handle.close() }

    func read(offset: Int64, length: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }
}

/// A photo's content hash (FS-19.02 §1). Covers only the **image data** —
/// never the EXIF, XMP or IPTC blocks — so another app writing stars or
/// keywords into the file does not make it a different photo.
struct ContentHash: Equatable, Sendable {
    static let algorithm = "sdx-image-sha256"
    /// Bump when what counts as image data changes; old hashes are then
    /// recomputed rather than compared.
    static let version = 1

    let algorithm: String
    let version: Int
    /// Size of the image data + its first, middle and last 64 KB: cheap to
    /// read, enough to follow a rename. Two photos may share one.
    let fast: String
    /// Every byte of the image data. Only this ever merges two copies.
    let full: String?
}

enum ContentHasher {
    static let sampleSize = 64 * 1024
    private static let blockSize = 1 << 20

    /// The hash of `bytes`; `full` false reads only the fast samples.
    static func hash(_ bytes: ContentBytes, full: Bool) throws -> ContentHash {
        let ranges = ImageDataLayout.ranges(in: bytes) ?? [0..<bytes.length]
        let stream = ImageDataStream(bytes: bytes, ranges: ranges)
        return ContentHash(
            algorithm: ContentHash.algorithm,
            version: ContentHash.version,
            fast: try fastHash(stream),
            full: full ? try fullHash(stream) : nil
        )
    }

    private static func fastHash(_ stream: ImageDataStream) throws -> String {
        var hasher = SHA256()
        var size = UInt64(stream.length).littleEndian
        withUnsafeBytes(of: &size) { hasher.update(bufferPointer: $0) }
        let sample = Int64(sampleSize)
        if stream.length <= sample * 3 {
            hasher.update(data: try stream.read(offset: 0, length: Int(stream.length)))
        } else {
            for start in [0, (stream.length - sample) / 2, stream.length - sample] {
                hasher.update(data: try stream.read(offset: start, length: sampleSize))
            }
        }
        return hex(hasher.finalize())
    }

    private static func fullHash(_ stream: ImageDataStream) throws -> String {
        var hasher = SHA256()
        var offset: Int64 = 0
        while offset < stream.length {
            let chunk = try stream.read(offset: offset, length: blockSize)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            offset += Int64(chunk.count)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// The image-data ranges of a file, read as one logical stream.
struct ImageDataStream {
    let bytes: ContentBytes
    let ranges: [Range<Int64>]
    let length: Int64

    init(bytes: ContentBytes, ranges: [Range<Int64>]) {
        self.bytes = bytes
        self.ranges = ranges
        length = ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    func read(offset: Int64, length wanted: Int) throws -> Data {
        var out = Data()
        var skip = offset
        var left = Int64(wanted)
        for range in ranges where left > 0 {
            let size = range.upperBound - range.lowerBound
            if skip >= size { skip -= size; continue }
            let take = min(size - skip, left)
            out.append(try bytes.read(offset: range.lowerBound + skip, length: Int(take)))
            left -= take
            skip = 0
        }
        return out
    }
}

/// Where the image data sits, per format. Nil means "not understood": the
/// whole file is hashed.
enum ImageDataLayout {
    static func ranges(in bytes: ContentBytes) -> [Range<Int64>]? {
        guard let head = try? bytes.read(offset: 0, length: 16), head.count >= 12 else { return nil }
        let b = [UInt8](head)
        if b[0] == 0xFF, b[1] == 0xD8 { return jpeg(bytes) }
        if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00)
            || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A) { return tiff(bytes) }
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return isobmff(bytes) }
        return nil
    }

    // MARK: JPEG — every segment but APPn and COM, then the scan to EOI.

    static func jpeg(_ bytes: ContentBytes) -> [Range<Int64>]? {
        var ranges: [Range<Int64>] = []
        var offset: Int64 = 2
        while offset + 4 <= bytes.length {
            guard let marker = try? [UInt8](bytes.read(offset: offset, length: 4)), marker.count == 4, marker[0] == 0xFF
            else { return nil }
            let code = marker[1]
            if code == 0xFF { offset += 1; continue }
            if code == 0xD9 { break }
            let segmentLength = Int64(marker[2]) << 8 | Int64(marker[3])
            let end = offset + 2 + segmentLength
            guard end <= bytes.length else { return nil }
            let isMetadata = (0xE0...0xEF).contains(code) || code == 0xFE
            if code == 0xDA {
                // Start of scan: from here the entropy-coded data runs to the end.
                ranges.append(offset..<bytes.length)
                return ranges
            }
            if !isMetadata { ranges.append(offset..<end) }
            offset = end
        }
        return ranges.isEmpty ? nil : ranges
    }

    // MARK: TIFF family — strips, tiles and embedded JPEGs of every IFD.

    static func tiff(_ bytes: ContentBytes) -> [Range<Int64>]? {
        guard let head = try? [UInt8](bytes.read(offset: 0, length: 8)), head.count == 8 else { return nil }
        let little = head[0] == 0x49
        func u16(_ d: [UInt8], _ i: Int) -> Int64 {
            little ? Int64(d[i]) | Int64(d[i + 1]) << 8 : Int64(d[i]) << 8 | Int64(d[i + 1])
        }
        func u32(_ d: [UInt8], _ i: Int) -> Int64 {
            little
                ? Int64(d[i]) | Int64(d[i + 1]) << 8 | Int64(d[i + 2]) << 16 | Int64(d[i + 3]) << 24
                : Int64(d[i]) << 24 | Int64(d[i + 1]) << 16 | Int64(d[i + 2]) << 8 | Int64(d[i + 3])
        }
        /// The values of one tag as offsets/counts (SHORT or LONG).
        func values(_ entry: [UInt8], _ base: Int) -> [Int64]? {
            let type = u16(entry, base + 2)
            let count = u32(entry, base + 4)
            let size: Int64 = type == 3 ? 2 : type == 4 || type == 13 ? 4 : 0
            guard size > 0, count > 0, count < 1_000_000 else { return nil }
            let total = size * count
            let data: [UInt8]
            if total <= 4 {
                data = Array(entry[(base + 8)..<(base + 12)])
            } else {
                guard let read = try? [UInt8](bytes.read(offset: u32(entry, base + 8), length: Int(total))),
                      read.count == Int(total) else { return nil }
                data = read
            }
            return (0..<Int(count)).map { size == 2 ? u16(data, $0 * 2) : u32(data, $0 * 4) }
        }

        var ranges: [Range<Int64>] = []
        var pending: [Int64] = [u32(head, 4)]
        var visited = Set<Int64>()
        while let ifd = pending.popLast() {
            guard ifd > 0, ifd < bytes.length, visited.insert(ifd).inserted, visited.count < 64,
                  let countBytes = try? [UInt8](bytes.read(offset: ifd, length: 2)), countBytes.count == 2 else { continue }
            let count = Int(u16(countBytes, 0))
            guard let entries = try? [UInt8](bytes.read(offset: ifd + 2, length: count * 12 + 4)),
                  entries.count == count * 12 + 4 else { continue }
            var tags: [Int64: [Int64]] = [:]
            for i in 0..<count {
                let tag = u16(entries, i * 12)
                if [273, 279, 324, 325, 330, 513, 514].contains(tag), let list = values(entries, i * 12) {
                    tags[tag] = list
                }
            }
            for (offsetsTag, countsTag) in [(Int64(273), Int64(279)), (324, 325), (513, 514)] {
                guard let offsets = tags[offsetsTag], let counts = tags[countsTag], offsets.count == counts.count else { continue }
                for (start, size) in zip(offsets, counts) where size > 0 && start + size <= bytes.length {
                    ranges.append(start..<(start + size))
                }
            }
            pending.append(contentsOf: tags[330] ?? [])
            pending.append(u32(entries, count * 12))
        }
        guard !ranges.isEmpty else { return nil }
        return Array(Set(ranges)).sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: ISOBMFF — HEIF items except Exif/XMP; otherwise (CR3) every mdat.

    static func isobmff(_ bytes: ContentBytes) -> [Range<Int64>]? {
        var mdats: [Range<Int64>] = []
        var meta: Range<Int64>?
        var offset: Int64 = 0
        while offset + 8 <= bytes.length {
            guard let (type, payload, end) = box(bytes, at: offset, limit: bytes.length) else { return nil }
            if type == "mdat" { mdats.append(payload) }
            if type == "meta" { meta = payload }
            offset = end
        }
        if let meta, let items = heifItemRanges(bytes, meta: meta) { return items }
        return mdats.isEmpty ? nil : mdats
    }

    /// (type, payload range, end) of the box at `offset`.
    private static func box(_ bytes: ContentBytes, at offset: Int64, limit: Int64) -> (String, Range<Int64>, Int64)? {
        guard let head = try? [UInt8](bytes.read(offset: offset, length: 16)), head.count >= 8 else { return nil }
        var size = Int64(head[0]) << 24 | Int64(head[1]) << 16 | Int64(head[2]) << 8 | Int64(head[3])
        let type = String(decoding: head[4..<8], as: UTF8.self)
        var header: Int64 = 8
        if size == 1 {
            guard head.count == 16 else { return nil }
            size = head[8..<16].reduce(Int64(0)) { $0 << 8 | Int64($1) }
            header = 16
        } else if size == 0 {
            size = limit - offset
        }
        guard size >= header, offset + size <= limit else { return nil }
        return (type, (offset + header)..<(offset + size), offset + size)
    }

    /// Extents of every item that is not Exif or XMP, in item order.
    private static func heifItemRanges(_ bytes: ContentBytes, meta: Range<Int64>) -> [Range<Int64>]? {
        // `meta` is a full box: 4 bytes of version/flags before its children.
        var offset = meta.lowerBound + 4
        var metadataItems = Set<Int64>()
        var locations: [(id: Int64, ranges: [Range<Int64>])] = []
        var idat: Range<Int64>?
        while offset + 8 <= meta.upperBound {
            guard let (type, payload, end) = box(bytes, at: offset, limit: meta.upperBound) else { return nil }
            switch type {
            case "iinf": metadataItems = parseIinf(bytes, payload) ?? []
            case "iloc": locations = parseIloc(bytes, payload) ?? []
            case "idat": idat = payload
            default: break
            }
            offset = end
        }
        guard !locations.isEmpty else { return nil }
        var out: [Range<Int64>] = []
        for location in locations.sorted(by: { $0.id < $1.id }) where !metadataItems.contains(location.id) {
            for range in location.ranges {
                // Negative lower bound marks an idat-relative extent.
                if range.lowerBound < 0, let idat {
                    let start = idat.lowerBound + (-range.lowerBound - 1)
                    out.append(start..<(start + (range.upperBound - range.lowerBound)))
                } else if range.lowerBound >= 0, range.upperBound <= bytes.length {
                    out.append(range)
                }
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Item ids whose type is `Exif`, or `mime` (XMP).
    private static func parseIinf(_ bytes: ContentBytes, _ payload: Range<Int64>) -> Set<Int64>? {
        guard let data = try? [UInt8](bytes.read(offset: payload.lowerBound, length: Int(payload.upperBound - payload.lowerBound))),
              data.count >= 6 else { return nil }
        let version = data[0]
        var cursor = version == 0 ? 6 : 8
        var ids = Set<Int64>()
        while cursor + 8 <= data.count {
            let size = Int(data[cursor]) << 24 | Int(data[cursor + 1]) << 16 | Int(data[cursor + 2]) << 8 | Int(data[cursor + 3])
            guard size >= 8, cursor + size <= data.count else { break }
            let type = String(decoding: data[(cursor + 4)..<(cursor + 8)], as: UTF8.self)
            if type == "infe", size >= 20 {
                let infeVersion = data[cursor + 8]
                if infeVersion >= 2 {
                    let id: Int64
                    let typeAt: Int
                    if infeVersion == 2 {
                        id = Int64(data[cursor + 12]) << 8 | Int64(data[cursor + 13])
                        typeAt = cursor + 16
                    } else {
                        id = Int64(data[cursor + 12]) << 24 | Int64(data[cursor + 13]) << 16 | Int64(data[cursor + 14]) << 8 | Int64(data[cursor + 15])
                        typeAt = cursor + 18
                    }
                    if typeAt + 4 <= cursor + size {
                        let itemType = String(decoding: data[typeAt..<(typeAt + 4)], as: UTF8.self)
                        if itemType == "Exif" || itemType == "mime" { ids.insert(id) }
                    }
                }
            }
            cursor += size
        }
        return ids
    }

    /// Extents per item; an idat extent is encoded as a negative lower bound.
    private static func parseIloc(_ bytes: ContentBytes, _ payload: Range<Int64>) -> [(id: Int64, ranges: [Range<Int64>])]? {
        guard let data = try? [UInt8](bytes.read(offset: payload.lowerBound, length: Int(payload.upperBound - payload.lowerBound))),
              data.count >= 8 else { return nil }
        let version = data[0]
        let offsetSize = Int(data[4] >> 4), lengthSize = Int(data[4] & 0x0F)
        let baseSize = Int(data[5] >> 4), indexSize = version >= 1 ? Int(data[5] & 0x0F) : 0
        var cursor = 6
        func read(_ size: Int) -> Int64? {
            guard size == 0 || [4, 8, 2].contains(size), cursor + size <= data.count else { return size == 0 ? 0 : nil }
            var value: Int64 = 0
            for i in 0..<size { value = value << 8 | Int64(data[cursor + i]) }
            cursor += size
            return value
        }
        guard let itemCount = read(version < 2 ? 2 : 4) else { return nil }
        var out: [(Int64, [Range<Int64>])] = []
        for _ in 0..<itemCount {
            guard let id = read(version < 2 ? 2 : 4) else { return nil }
            var method: Int64 = 0
            if version >= 1 {
                guard let packed = read(2) else { return nil }
                method = packed & 0x0F
            }
            guard read(2) != nil, let base = read(baseSize), let extents = read(2) else { return nil }
            var ranges: [Range<Int64>] = []
            for _ in 0..<extents {
                if indexSize > 0 { guard read(indexSize) != nil else { return nil } }
                guard let extentOffset = read(offsetSize), let extentLength = read(lengthSize) else { return nil }
                let start = base + extentOffset
                if method == 1 {
                    ranges.append(-(start + 1)..<(-(start + 1) + extentLength))
                } else if method == 0 {
                    ranges.append(start..<(start + extentLength))
                }
            }
            out.append((id, ranges))
        }
        return out
    }
}
