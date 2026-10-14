import Foundation

/// Cover art inside an MP4/M4V/MOV (`moov/udta/meta/ilst/covr/data`),
/// found by reading box headers and the `moov` box only — never the media
/// (FS-23.01 §4: a scan may read an MP4's cover). `moov` can sit at the end
/// of the file; the walk finds it there too.
enum MP4CoverArt {
    /// A `moov` larger than this is a long movie's sample tables, not worth
    /// reading for a poster.
    static let maxMoovBytes = 24 << 20

    static func find(size: Int64, read: (Int64, Int) async throws -> Data) async throws -> Data? {
        var offset: Int64 = 0
        var boxes = 0
        while offset + 8 <= size, boxes < 64 {
            boxes += 1
            let head = try await read(offset, 16)
            guard head.count >= 8, let (length, type, headerLength) = boxHeader(head, remaining: size - offset) else { return nil }
            if type == "moov" {
                guard length <= Int64(maxMoovBytes) else { return nil }
                let moov = try await read(offset + Int64(headerLength), Int(length) - headerLength)
                return cover(inMoov: moov)
            }
            offset += length
        }
        return nil
    }

    /// The `data` payload of the first `covr` under `moov`.
    static func cover(inMoov moov: Data) -> Data? {
        guard let udta = child("udta", in: moov),
              let meta = child("meta", in: udta),
              // `meta` is a full box: four bytes of version and flags first.
              let ilst = child("ilst", in: meta.count > 4 ? meta.dropFirst(4) : meta) ?? child("ilst", in: meta),
              let covr = child("covr", in: ilst),
              let data = child("data", in: covr), data.count > 8 else { return nil }
        // `data`: 4 bytes type indicator, 4 bytes locale, then the image.
        return Data(data.dropFirst(8))
    }

    /// The payload of the first child box named `type`.
    private static func child(_ type: String, in container: Data) -> Data? {
        var index = container.startIndex
        while index + 8 <= container.endIndex {
            let head = container[index..<min(container.endIndex, index + 16)]
            guard let (length, name, headerLength) = boxHeader(Data(head), remaining: Int64(container.endIndex - index)),
                  length >= Int64(headerLength) else { return nil }
            let end = index + Int(length)
            guard end <= container.endIndex else { return nil }
            if name == type { return Data(container[(index + headerLength)..<end]) }
            index = end
        }
        return nil
    }

    /// (total length, four-character type, header length). Size 0 means
    /// "to the end"; size 1 means a 64-bit size follows the type.
    private static func boxHeader(_ bytes: Data, remaining: Int64) -> (Int64, String, Int)? {
        let b = [UInt8](bytes.prefix(16))
        guard b.count >= 8 else { return nil }
        let size32 = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        guard let type = String(bytes: b[4..<8], encoding: .isoLatin1) else { return nil }
        switch size32 {
        case 0: return (remaining, type, 8)
        case 1:
            guard b.count >= 16 else { return nil }
            let size64 = b[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            guard size64 >= 16, size64 <= UInt64(Int64.max) else { return nil }
            return (Int64(size64), type, 16)
        default:
            guard size32 >= 8 else { return nil }
            return (Int64(size32), type, 8)
        }
    }
}
