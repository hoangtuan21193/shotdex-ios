import Compression
import Foundation

/// The files in a `.zip` (FS-23.03 §5: a subtitle pack). Reads the central
/// directory, then each entry stored or deflated — the two methods zip
/// tools write; anything else (and encrypted entries) is skipped. iOS has
/// no unzip API, and this is all a subtitle pack needs.
enum ZipReader {
    struct Entry: Equatable, Sendable {
        var name: String
        var data: Data
    }

    enum Failure: Error, Equatable {
        case notZip
    }

    /// Entries bigger than this are not subtitles and are skipped.
    static let entryLimit = 16 << 20

    static func entries(_ zip: Data, accepting accept: (String) -> Bool = { _ in true }) throws -> [Entry] {
        let bytes = [UInt8](zip)
        guard let end = endOfCentralDirectory(bytes) else { throw Failure.notZip }
        let count = Int(u16(bytes, end + 10))
        var position = Int(u32(bytes, end + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard position + 46 <= bytes.count, u32(bytes, position) == 0x0201_4B50 else { break }
            let flags = u16(bytes, position + 8)
            let method = u16(bytes, position + 10)
            let compressed = Int(u32(bytes, position + 20))
            let size = Int(u32(bytes, position + 24))
            let nameLength = Int(u16(bytes, position + 28))
            let extraLength = Int(u16(bytes, position + 30))
            let commentLength = Int(u16(bytes, position + 32))
            let local = Int(u32(bytes, position + 42))
            let nameBytes = Array(bytes[(position + 46)..<min(bytes.count, position + 46 + nameLength)])
            let name = String(bytes: nameBytes, encoding: flags & 0x0800 != 0 ? .utf8 : .isoLatin1) ?? ""
            position += 46 + nameLength + extraLength + commentLength

            guard !name.hasSuffix("/"), flags & 0x0001 == 0, size <= entryLimit,
                  !name.hasPrefix("__MACOSX/"), accept(name) else { continue }
            guard local + 30 <= bytes.count, u32(bytes, local) == 0x0403_4B50 else { continue }
            let start = local + 30 + Int(u16(bytes, local + 26)) + Int(u16(bytes, local + 28))
            guard start + compressed <= bytes.count else { continue }
            let raw = Array(bytes[start..<(start + compressed)])
            switch method {
            case 0: entries.append(Entry(name: name, data: Data(raw)))
            case 8:
                if let inflated = inflate(raw, size: size) { entries.append(Entry(name: name, data: inflated)) }
            default: continue
            }
        }
        return entries
    }

    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        // The record sits in the last 22 + 65 535 (comment) bytes.
        let lowest = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= lowest {
            if u32(bytes, index) == 0x0605_4B50 { return index }
            index -= 1
        }
        return nil
    }

    private static func inflate(_ deflated: [UInt8], size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(&output, size, deflated, deflated.count, nil, COMPRESSION_ZLIB)
        return written == size ? Data(output) : nil
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        guard at + 1 < bytes.count else { return 0 }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        guard at + 3 < bytes.count else { return 0 }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
