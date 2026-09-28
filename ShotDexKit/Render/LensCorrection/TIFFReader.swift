import Foundation

// Moved from the app's MakerNoteParser (FS-03.16a §1): the shutter counter
// and the lens-correction readers walk the same TIFF structures.

/// One parsed IFD entry: its type, count, and the absolute file offset of its
/// 4-byte value/offset field (inline value when it fits, else a pointer).
public struct IFDEntry: Sendable {
    public let type: Int
    public let count: Int
    /// Absolute file offset of the entry's value field (the last 4 bytes of the
    /// 12-byte entry).
    public let valueFieldOffset: Int
}

/// Minimal TIFF/Exif reader over a byte buffer. `base` is the TIFF header
/// origin (the origin for all IFD/value offsets in this structure).
public struct TIFFReader: Sendable {
    public let bytes: [UInt8]
    public let base: Int
    public let isLittleEndian: Bool
    public let firstIFDOffset: Int

    /// Parses the TIFF header at `base` (byte order + first-IFD offset).
    public init?(bytes: [UInt8], base: Int) {
        guard base >= 0, base + 8 <= bytes.count else { return nil }
        let isLittleEndian: Bool
        if bytes[base] == 0x49, bytes[base + 1] == 0x49 {
            isLittleEndian = true
        } else if bytes[base] == 0x4D, bytes[base + 1] == 0x4D {
            isLittleEndian = false
        } else {
            return nil
        }
        guard let ifdOffset = TIFFReader.readUInt32(bytes, at: base + 4, isLittleEndian: isLittleEndian) else { return nil }
        self.bytes = bytes
        self.base = base
        self.isLittleEndian = isLittleEndian
        self.firstIFDOffset = Int(ifdOffset)
    }

    /// Builds a reader with an explicit byte order / first-IFD offset (for
    /// self-contained vendor notes like Fuji that carry no TIFF header).
    public init?(bytes: [UInt8], base: Int, isLittleEndian: Bool, firstIFDOffset: Int) {
        guard base >= 0, base <= bytes.count else { return nil }
        self.bytes = bytes
        self.base = base
        self.isLittleEndian = isLittleEndian
        self.firstIFDOffset = firstIFDOffset
    }

    /// Parses the IFD at absolute offset `ifdAbs`. `offsetBase` is the origin
    /// its stored value pointers resolve against. Returns tag → entry.
    public func ifd(atAbsolute ifdAbs: Int, offsetBase: Int) -> [Int: IFDEntry]? {
        guard ifdAbs >= 0, ifdAbs + 2 <= bytes.count else { return nil }
        guard let count = readUInt16(at: ifdAbs) else { return nil }
        let entriesStart = ifdAbs + 2
        guard entriesStart + count * 12 <= bytes.count else { return nil }
        var result: [Int: IFDEntry] = [:]
        result.reserveCapacity(count)
        for index in 0..<count {
            let entryStart = entriesStart + index * 12
            guard let tag = readUInt16(at: entryStart),
                  let type = readUInt16(at: entryStart + 2),
                  let rawCount = TIFFReader.readUInt32(bytes, at: entryStart + 4, isLittleEndian: isLittleEndian)
            else { continue }
            result[tag] = IFDEntry(type: type, count: Int(rawCount), valueFieldOffset: entryStart + 8)
        }
        return result
    }

    /// Absolute start of an entry's data: the inline value field when it fits in
    /// 4 bytes, otherwise the pointer it holds resolved against `offsetBase`.
    public func dataStart(of entry: IFDEntry, offsetBase: Int) -> Int {
        let size = entry.count * Self.typeSize(entry.type)
        if size <= 4 {
            return entry.valueFieldOffset
        }
        guard let pointer = TIFFReader.readUInt32(bytes, at: entry.valueFieldOffset, isLittleEndian: isLittleEndian) else {
            return -1
        }
        return offsetBase + Int(pointer)
    }

    /// Reads a SHORT/LONG entry's first value as an Int.
    public func longValue(_ entry: IFDEntry, offsetBase: Int) -> Int? {
        let start = dataStart(of: entry, offsetBase: offsetBase)
        guard start >= 0 else { return nil }
        switch entry.type {
        case 3:  // SHORT
            return readUInt16(at: start)
        case 4:  // LONG
            return TIFFReader.readUInt32(bytes, at: start, isLittleEndian: isLittleEndian).map(Int.init)
        default:
            return TIFFReader.readUInt32(bytes, at: start, isLittleEndian: isLittleEndian).map(Int.init)
        }
    }

    public func readUInt16(at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return isLittleEndian
            ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            : Int(bytes[offset + 1]) | Int(bytes[offset]) << 8
    }

    /// Byte size of a TIFF field type (BYTE/ASCII/UNDEFINED=1, SHORT=2,
    /// LONG/RATIONAL-word=4, …). Defaults to 1 for unknown types.
    public static func typeSize(_ type: Int) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1   // BYTE, ASCII, SBYTE, UNDEFINED
        case 3, 8: return 2         // SHORT, SSHORT
        case 4, 9, 11: return 4     // LONG, SLONG, FLOAT
        case 5, 10, 12: return 8    // RATIONAL, SRATIONAL, DOUBLE
        default: return 1
        }
    }

    public func readUInt32(at offset: Int) -> Int? {
        Self.readUInt32(bytes, at: offset, isLittleEndian: isLittleEndian).map(Int.init)
    }

    public static func readUInt32(_ bytes: [UInt8], at offset: Int, isLittleEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let b = (0..<4).map { UInt32(bytes[offset + $0]) }
        return isLittleEndian
            ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24
            : b[3] | b[2] << 8 | b[1] << 16 | b[0] << 24
    }
}
