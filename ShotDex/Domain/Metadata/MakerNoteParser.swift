import Foundation

/// Extracts the camera's total shutter-actuation count from the raw MakerNote
/// block of an original image file. ImageIO does **not** decode MakerNotes into
/// named keys, so this parses the TIFF/Exif structure itself, locates the
/// MakerNote (Exif tag `0x927C`), and reads the vendor-specific counter —
/// mirroring how the free online shutter-count checkers (ExifTool) do it.
///
/// Pure Swift over raw bytes, no framework dependency (fits the testable Domain
/// layer). Only works on the **original, unedited file** — edits strip the
/// MakerNote. Vendors:
/// - **Nikon**: MakerNote tag `0x00A7`, plaintext. Reliable.
/// - **Sony**: tag `0x9050`, enciphered with a `(b³ % 249)` byte permutation;
///   deciphered, then the count read at a model-specific offset. Best-effort —
///   newest bodies shift offsets and return nil.
/// - **Fujifilm**: tag `0x1438` (ImageCount), plaintext. Best-effort.
/// - **Canon**: not stored in image files (camera-memory only) → nil.
enum MakerNoteParser {

    /// Reads the shutter count from `data` (the original file's bytes). Returns
    /// nil when the vendor is unsupported, the MakerNote is absent/stripped, or
    /// the value fails a sanity check.
    static func shutterCount(from data: Data, make: String?, model: String?) -> Int? {
        let bytes = [UInt8](data)
        guard let base = tiffBase(in: bytes) else { return nil }
        guard let header = TIFFReader(bytes: bytes, base: base) else { return nil }

        // IFD0 → Exif IFD pointer (0x8769).
        guard let ifd0 = header.ifd(atAbsolute: base + header.firstIFDOffset, offsetBase: base),
              let exifPtr = ifd0[0x8769].flatMap({ header.longValue($0, offsetBase: base) }),
              let exifIFD = header.ifd(atAbsolute: base + exifPtr, offsetBase: base),
              let makerEntry = exifIFD[0x927C]
        else { return nil }

        // Absolute start of the MakerNote blob.
        let makerStart = header.dataStart(of: makerEntry, offsetBase: base)
        guard makerStart >= 0, makerStart < bytes.count else { return nil }

        let vendor = (make ?? "").uppercased()
        if vendor.contains("NIKON") {
            return nikonCount(bytes: bytes, makerStart: makerStart, tiffBase: base, tiffHeader: header)
        }
        if vendor.contains("SONY") {
            return sonyCount(bytes: bytes, makerEntry: makerEntry, header: header, tiffBase: base, model: model)
        }
        if vendor.contains("FUJI") {
            return fujiCount(bytes: bytes, makerStart: makerStart)
        }
        return nil
    }

    /// Whether shutter count is readable from a file for this camera make.
    /// Canon (camera-memory only) and unknown makes are unsupported, so callers
    /// can skip fetching the original bytes.
    static func isSupportedVendor(_ make: String) -> Bool {
        let vendor = make.uppercased()
        return vendor.contains("NIKON") || vendor.contains("SONY") || vendor.contains("FUJI")
    }

    // MARK: - Vendor readers

    /// Nikon type-2 MakerNote: `"Nikon\0"` + version + an embedded, self-contained
    /// TIFF whose IFD holds tag `0x00A7` (ShutterCount, plaintext LONG). Older
    /// type-1 notes have no header and share the outer TIFF's offset base.
    private static func nikonCount(bytes: [UInt8], makerStart: Int, tiffBase: Int, tiffHeader: TIFFReader) -> Int? {
        if matches(bytes, at: makerStart, ascii: "Nikon"), bytes.count > makerStart + 10 {
            // Embedded TIFF header lives at makerStart + 10; its offsets are
            // relative to that embedded header, not the outer file.
            let embeddedBase = makerStart + 10
            guard let embedded = TIFFReader(bytes: bytes, base: embeddedBase),
                  let ifd = embedded.ifd(atAbsolute: embeddedBase + embedded.firstIFDOffset, offsetBase: embeddedBase),
                  let entry = ifd[0x00A7],
                  let value = embedded.longValue(entry, offsetBase: embeddedBase)
            else { return nil }
            return plausibleShutterCount(value)
        }
        // Type-1: parse an IFD directly at the MakerNote start against the outer
        // TIFF base.
        guard let ifd = tiffHeader.ifd(atAbsolute: makerStart, offsetBase: tiffBase),
              let entry = ifd[0x00A7],
              let value = tiffHeader.longValue(entry, offsetBase: tiffBase)
        else { return nil }
        return plausibleShutterCount(value)
    }

    /// Sony hides the count in tag `0x9050`, whose bytes are enciphered with a
    /// fixed `(b³ % 249)` permutation. Decipher, then read an int32u at a
    /// model-specific offset. Offsets cover common Alpha bodies; unknown models
    /// return nil (same limitation as ExifTool).
    private static func sonyCount(
        bytes: [UInt8],
        makerEntry: IFDEntry,
        header: TIFFReader,
        tiffBase: Int,
        model: String?
    ) -> Int? {
        guard let offset = sonyOffset(forModel: model) else { return nil }
        // Sony MakerNote IFD entry value offsets resolve against the outer TIFF
        // base. Parse the note's own IFD to find tag 0x9050.
        let makerStart = header.dataStart(of: makerEntry, offsetBase: tiffBase)
        guard let ifd = header.ifd(atAbsolute: makerStart, offsetBase: tiffBase),
              let entry = ifd[0x9050]
        else { return nil }
        let blockStart = header.dataStart(of: entry, offsetBase: tiffBase)
        let blockLen = entry.count
        guard blockStart >= 0, blockLen >= offset + 4, blockStart + blockLen <= bytes.count else { return nil }

        let decode = Self.sonyDecodeTable
        // Decipher only the four bytes we need.
        var value: UInt32 = 0
        for i in 0..<4 {
            let enciphered = bytes[blockStart + offset + i]
            let plain = decode[Int(enciphered)]
            value |= UInt32(plain) << (8 * i)   // little-endian int32u
        }
        return plausibleShutterCount(Int(value))
    }

    /// Fujifilm MakerNote: `"FUJIFILM"` + a 4-byte little-endian offset (relative
    /// to the note start) to its IFD, which is always little-endian. Tag `0x1438`
    /// carries an image counter. Best-effort.
    private static func fujiCount(bytes: [UInt8], makerStart: Int) -> Int? {
        guard matches(bytes, at: makerStart, ascii: "FUJIFILM"), bytes.count > makerStart + 12 else { return nil }
        let ifdOffset = readUInt32(bytes, at: makerStart + 8, isLittleEndian: true)
        guard let ifdOffset else { return nil }
        let ifdAbs = makerStart + Int(ifdOffset)
        // Fuji notes are self-contained: offsets relative to the note start.
        guard let reader = TIFFReader(bytes: bytes, base: makerStart, isLittleEndian: true, firstIFDOffset: Int(ifdOffset)),
              let ifd = reader.ifd(atAbsolute: ifdAbs, offsetBase: makerStart),
              let entry = ifd[0x1438],
              let value = reader.longValue(entry, offsetBase: makerStart)
        else { return nil }
        return plausibleShutterCount(value)
    }

    // MARK: - Sony cipher / offsets

    /// Model → byte offset of the shutter count inside the deciphered `0x9050`
    /// block. Matched on the Sony `ILCE-*` model code. Documented offsets for
    /// common bodies; newest/unknown models omitted (return nil).
    private static func sonyOffset(forModel model: String?) -> Int? {
        guard let model = model?.uppercased() else { return nil }
        // 0x003a — A7 III / A7 IV / A9 III / A1.
        for code in ["ILCE-7M3", "ILCE-7M4", "ILCE-9M3", "ILCE-1"] where model == code {
            return 0x3A
        }
        // 0x000a — A7CR / A6700 / A1 II / A7 V.
        for code in ["ILCE-7CR", "ILCE-6700", "ILCE-1M2", "ILCE-7M5"] where model == code {
            return 0x0A
        }
        // 0x0032 — A7 / A7 II.
        for code in ["ILCE-7", "ILCE-7M2"] where model == code {
            return 0x32
        }
        return nil
    }

    /// Inverse of Sony's enciphering permutation: the camera stores byte `b` as
    /// `(b³ % 249)` for `b < 249` (identity for 249…255). This table maps an
    /// enciphered byte back to its plaintext value.
    private static let sonyDecodeTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for plain in 0..<249 {
            let enciphered = (plain * plain * plain) % 249
            table[enciphered] = UInt8(plain)
        }
        for identity in 249..<256 {
            table[identity] = UInt8(identity)
        }
        return table
    }()

    // MARK: - Helpers

    /// A shutter count outside this range is almost certainly a mis-parse.
    private static func plausibleShutterCount(_ value: Int) -> Int? {
        (value > 0 && value < 50_000_000) ? value : nil
    }

    private static func matches(_ bytes: [UInt8], at offset: Int, ascii: String) -> Bool {
        let pattern = Array(ascii.utf8)
        guard offset >= 0, offset + pattern.count <= bytes.count else { return false }
        for (i, byte) in pattern.enumerated() where bytes[offset + i] != byte {
            return false
        }
        return true
    }

    /// Finds the TIFF header origin: byte 0 for TIFF-based files (NEF/ARW/…),
    /// just past JPEG `APP1`/`Exif\0\0`, or inside the embedded JPEG carried by
    /// Fujifilm RAF. RAF does not start with TIFF/JPEG, which was why its
    /// advertised ImageCount support previously never ran for actual `.RAF`
    /// originals.
    private static func tiffBase(in bytes: [UInt8]) -> Int? {
        guard bytes.count > 8 else { return nil }
        // Direct TIFF ("II"/"MM").
        if (bytes[0] == 0x49 && bytes[1] == 0x49) || (bytes[0] == 0x4D && bytes[1] == 0x4D) {
            return 0
        }

        if bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return jpegTIFFBase(in: bytes, jpegStart: 0)
        }

        // RAF offset directory: magic (16) + version/id/camera (44) +
        // directory version/reserved (24), then big-endian JPEG offset at 84.
        if matches(bytes, at: 0, ascii: "FUJIFILMCCD-RAW"),
           let jpegOffset = readUInt32(bytes, at: 84, isLittleEndian: false) {
            return jpegTIFFBase(in: bytes, jpegStart: Int(jpegOffset))
        }
        return nil
    }

    private static func jpegTIFFBase(in bytes: [UInt8], jpegStart: Int) -> Int? {
        guard jpegStart >= 0,
              jpegStart + 4 < bytes.count,
              bytes[jpegStart] == 0xFF,
              bytes[jpegStart + 1] == 0xD8
        else { return nil }
        var i = jpegStart + 2
        while i + 4 < bytes.count {
            guard bytes[i] == 0xFF else { i += 1; continue }
            let marker = bytes[i + 1]
            if marker == 0xD8 || marker == 0xD9 { i += 2; continue }
            let segLen = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker == 0xE1, matches(bytes, at: i + 4, ascii: "Exif") {
                return i + 4 + 6   // skip "Exif\0\0"
            }
            if segLen < 2 { return nil }
            i += 2 + segLen
        }
        return nil
    }

    fileprivate static func readUInt32(_ bytes: [UInt8], at offset: Int, isLittleEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let b = (0..<4).map { UInt32(bytes[offset + $0]) }
        return isLittleEndian
            ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24
            : b[3] | b[2] << 8 | b[1] << 16 | b[0] << 24
    }
}

/// One parsed IFD entry: its type, count, and the absolute file offset of its
/// 4-byte value/offset field (inline value when it fits, else a pointer).
struct IFDEntry {
    let type: Int
    let count: Int
    /// Absolute file offset of the entry's value field (the last 4 bytes of the
    /// 12-byte entry).
    let valueFieldOffset: Int
}

/// Minimal TIFF/Exif reader over a byte buffer. `base` is the TIFF header
/// origin (the origin for all IFD/value offsets in this structure).
struct TIFFReader {
    let bytes: [UInt8]
    let base: Int
    let isLittleEndian: Bool
    let firstIFDOffset: Int

    /// Parses the TIFF header at `base` (byte order + first-IFD offset).
    init?(bytes: [UInt8], base: Int) {
        guard base >= 0, base + 8 <= bytes.count else { return nil }
        let isLittleEndian: Bool
        if bytes[base] == 0x49, bytes[base + 1] == 0x49 {
            isLittleEndian = true
        } else if bytes[base] == 0x4D, bytes[base + 1] == 0x4D {
            isLittleEndian = false
        } else {
            return nil
        }
        guard let ifdOffset = MakerNoteParser.readUInt32(bytes, at: base + 4, isLittleEndian: isLittleEndian) else { return nil }
        self.bytes = bytes
        self.base = base
        self.isLittleEndian = isLittleEndian
        self.firstIFDOffset = Int(ifdOffset)
    }

    /// Builds a reader with an explicit byte order / first-IFD offset (for
    /// self-contained vendor notes like Fuji that carry no TIFF header).
    init?(bytes: [UInt8], base: Int, isLittleEndian: Bool, firstIFDOffset: Int) {
        guard base >= 0, base <= bytes.count else { return nil }
        self.bytes = bytes
        self.base = base
        self.isLittleEndian = isLittleEndian
        self.firstIFDOffset = firstIFDOffset
    }

    /// Parses the IFD at absolute offset `ifdAbs`. `offsetBase` is the origin
    /// its stored value pointers resolve against. Returns tag → entry.
    func ifd(atAbsolute ifdAbs: Int, offsetBase: Int) -> [Int: IFDEntry]? {
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
                  let rawCount = MakerNoteParser.readUInt32(bytes, at: entryStart + 4, isLittleEndian: isLittleEndian)
            else { continue }
            result[tag] = IFDEntry(type: type, count: Int(rawCount), valueFieldOffset: entryStart + 8)
        }
        return result
    }

    /// Absolute start of an entry's data: the inline value field when it fits in
    /// 4 bytes, otherwise the pointer it holds resolved against `offsetBase`.
    func dataStart(of entry: IFDEntry, offsetBase: Int) -> Int {
        let size = entry.count * Self.typeSize(entry.type)
        if size <= 4 {
            return entry.valueFieldOffset
        }
        guard let pointer = MakerNoteParser.readUInt32(bytes, at: entry.valueFieldOffset, isLittleEndian: isLittleEndian) else {
            return -1
        }
        return offsetBase + Int(pointer)
    }

    /// Reads a SHORT/LONG entry's first value as an Int.
    func longValue(_ entry: IFDEntry, offsetBase: Int) -> Int? {
        let start = dataStart(of: entry, offsetBase: offsetBase)
        guard start >= 0 else { return nil }
        switch entry.type {
        case 3:  // SHORT
            return readUInt16(at: start)
        case 4:  // LONG
            return MakerNoteParser.readUInt32(bytes, at: start, isLittleEndian: isLittleEndian).map(Int.init)
        default:
            return MakerNoteParser.readUInt32(bytes, at: start, isLittleEndian: isLittleEndian).map(Int.init)
        }
    }

    func readUInt16(at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return isLittleEndian
            ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            : Int(bytes[offset + 1]) | Int(bytes[offset]) << 8
    }

    /// Byte size of a TIFF field type (BYTE/ASCII/UNDEFINED=1, SHORT=2,
    /// LONG/RATIONAL-word=4, …). Defaults to 1 for unknown types.
    private static func typeSize(_ type: Int) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1   // BYTE, ASCII, SBYTE, UNDEFINED
        case 3, 8: return 2         // SHORT, SSHORT
        case 4, 9, 11: return 4     // LONG, SLONG, FLOAT
        case 5, 10, 12: return 8    // RATIONAL, SRATIONAL, DOUBLE
        default: return 1
        }
    }
}
