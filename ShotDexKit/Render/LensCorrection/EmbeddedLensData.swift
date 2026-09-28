import CoreGraphics
import Foundation

/// A curve over radius: linear between knots, flat past the ends.
public struct RadialCurve: Equatable, Sendable {
    public var radii: [Double]
    public var values: [Double]

    public init(radii: [Double], values: [Double]) {
        self.radii = radii
        self.values = values
    }

    public func value(at r: Double) -> Double {
        guard let first = radii.first, let last = radii.last, values.count == radii.count else { return 1 }
        if r <= first { return values[0] }
        if r >= last { return values[values.count - 1] }
        let upper = radii.firstIndex { $0 >= r } ?? radii.count - 1
        let a = radii[upper - 1], b = radii[upper]
        let t = b > a ? (r - a) / (b - a) : 0
        return values[upper - 1] + (values[upper] - values[upper - 1]) * t
    }
}

/// The maker's own lens correction read from a file (FS-03.16a §1), in the
/// common form every source reduces to: by radius, how far out to sample
/// (distortion), how much further out red and blue lie than green (CA), and
/// the gain that takes the vignetting out.
public struct EmbeddedLensCorrection: Equatable, Sendable {
    /// What radius 1 is, on the decoded frame.
    public enum RadiusUnit: Sendable, Equatable {
        /// Half the frame's diagonal (Sony, Fujifilm).
        case halfDiagonal
        /// Half the frame's long side (Panasonic).
        case halfLongSide
        /// The distance from the optical centre to the farthest corner (DNG).
        case farthestCorner
    }

    public var unit: RadiusUnit
    /// Optical centre, 0…1 of the frame, y down (DNG); the middle otherwise.
    public var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Source radius over output radius, green.
    public var distortion: RadialCurve?
    /// Red and blue radius over green.
    public var red: RadialCurve?
    public var blue: RadialCurve?
    /// Gain at each radius.
    public var vignetting: RadialCurve?

    public init(unit: RadiusUnit, center: CGPoint = CGPoint(x: 0.5, y: 0.5), distortion: RadialCurve? = nil,
                red: RadialCurve? = nil, blue: RadialCurve? = nil, vignetting: RadialCurve? = nil) {
        self.unit = unit
        self.center = center
        self.distortion = distortion
        self.red = red
        self.blue = blue
        self.vignetting = vignetting
    }

    public var hasDistortion: Bool { distortion != nil }
    public var hasChromaticAberration: Bool { red != nil || blue != nil }
    public var hasVignetting: Bool { vignetting != nil }

    /// The trust limits of 16a §1: a distortion that moves the corner by
    /// more than 15% of the radius, a gain outside 1–4×, or a CA offset over
    /// 0.5% is a misread, and that aspect is treated as absent.
    public func trusted() -> EmbeddedLensCorrection {
        var copy = self
        if let d = distortion, d.values.contains(where: { abs($0 - 1) > 0.15 || !$0.isFinite }) { copy.distortion = nil }
        for keyPath in [\EmbeddedLensCorrection.red, \EmbeddedLensCorrection.blue] {
            if let c = copy[keyPath: keyPath], c.values.contains(where: { abs($0 - 1) > 0.005 || !$0.isFinite }) {
                copy.red = nil
                copy.blue = nil
            }
        }
        if let v = vignetting, v.values.contains(where: { $0 < 0.999 || $0 > 4 || !$0.isFinite }) { copy.vignetting = nil }
        return copy
    }

    public var isEmpty: Bool { !hasDistortion && !hasChromaticAberration && !hasVignetting }
}

/// Reads the maker's lens-correction data out of a RAW (FS-03.16a §1).
/// Written from the formats' public descriptions and checked against the
/// correction Apple's decoder applies from the same data (DNG, Panasonic)
/// or the camera's own preview (Sony vignetting); no code from GPL projects.
public enum EmbeddedLensDataReader {

    public static func read(url: URL) -> EmbeddedLensCorrection? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return read(bytes: [UInt8](data))
    }

    public static func read(bytes: [UInt8]) -> EmbeddedLensCorrection? {
        let found: EmbeddedLensCorrection?
        if bytes.count > 16, String(bytes: bytes[0..<15], encoding: .ascii) == "FUJIFILMCCD-RAW" {
            found = fujifilm(bytes)
        } else {
            found = tiffBased(bytes)
        }
        guard let trusted = found?.trusted(), !trusted.isEmpty else { return nil }
        return trusted
    }

    // MARK: TIFF-based (DNG, Sony, Panasonic)

    static func tiffBased(_ bytes: [UInt8]) -> EmbeddedLensCorrection? {
        // RW2 opens "IIU\0" rather than "II*\0"; the IFD layout is TIFF's.
        guard let reader = TIFFReader(bytes: bytes, base: 0) else { return nil }
        guard let ifd0 = reader.ifd(atAbsolute: reader.firstIFDOffset, offsetBase: 0) else { return nil }
        if let info = ifd0[0x0119] {
            return panasonic(reader.slice(info, offsetBase: 0))
        }
        var ifds = [ifd0]
        if let sub = ifd0[0x014a] {
            let start = reader.dataStart(of: sub, offsetBase: 0)
            for index in 0..<min(sub.count, 8) {
                if let offset = reader.readUInt32(at: sub.count == 1 ? sub.valueFieldOffset : start + index * 4),
                   let ifd = reader.ifd(atAbsolute: offset, offsetBase: 0) {
                    ifds.append(ifd)
                }
            }
        }
        for ifd in ifds {
            if let opcodes = ifd[0xc74e] ?? ifd[0xc740], let dng = dng(reader.slice(opcodes, offsetBase: 0)) {
                return dng
            }
            if ifd[0x7037] != nil || ifd[0x7032] != nil || ifd[0x7035] != nil {
                return sony(ifd, reader: reader)
            }
        }
        return nil
    }

    /// DNG OpcodeList3's WarpRectilinear (DNG 1.3 §6): per plane
    /// kr0…kr3, kt0, kt1, then the centre; the source radius is
    /// r · (kr0 + kr1 r² + kr2 r⁴ + kr3 r⁶), r normalised to the farthest
    /// corner. Three planes are R, G, B — the lateral CA; one plane is all.
    static func dng(_ opcodes: [UInt8]) -> EmbeddedLensCorrection? {
        var cursor = BigEndianCursor(bytes: opcodes)
        guard let count = cursor.uint32(), count < 64 else { return nil }
        for _ in 0..<count {
            guard let id = cursor.uint32(), cursor.uint32() != nil, cursor.uint32() != nil,
                  let size = cursor.uint32() else { return nil }
            let end = cursor.offset + Int(size)
            guard end <= opcodes.count else { return nil }
            if id == 1 {
                guard let planes = cursor.uint32(), (1...4).contains(planes) else { return nil }
                var radial: [[Double]] = []
                for _ in 0..<planes {
                    var k: [Double] = []
                    for _ in 0..<6 { guard let v = cursor.double() else { return nil }; k.append(v) }
                    radial.append(Array(k[0..<4]))
                }
                guard let cx = cursor.double(), let cy = cursor.double() else { return nil }
                let radii = stride(from: 0.0, through: 1.2, by: 0.02).map { $0 }
                func curve(_ k: [Double]) -> RadialCurve {
                    RadialCurve(radii: radii, values: radii.map { r in
                        let r2 = r * r
                        return k[0] + k[1] * r2 + k[2] * r2 * r2 + k[3] * r2 * r2 * r2
                    })
                }
                let green = curve(radial[planes >= 3 ? 1 : 0])
                var correction = EmbeddedLensCorrection(
                    unit: .farthestCorner, center: CGPoint(x: cx, y: cy), distortion: green
                )
                if planes >= 3 {
                    let r = curve(radial[0]), b = curve(radial[2])
                    correction.red = RadialCurve(radii: radii, values: zip(r.values, green.values).map { $0 / $1 })
                    correction.blue = RadialCurve(radii: radii, values: zip(b.values, green.values).map { $0 / $1 })
                }
                return correction
            }
            cursor.offset = end
        }
        return nil
    }

    /// Sony ARW, raw SubIFD: 0x7032 vignetting, 0x7035 CA, 0x7037
    /// distortion — each a count then that many int16 knots spread evenly
    /// from the centre to the corner (half-diagonal). Distortion scale
    /// 1 + v·2⁻¹⁴; CA 1 + v·2⁻²¹ for red then blue; vignetting gain
    /// 1 / 2^(0.5 − 2^(v·2⁻¹³ − 1)).
    static func sony(_ ifd: [Int: IFDEntry], reader: TIFFReader) -> EmbeddedLensCorrection? {
        func knots(_ tag: Int) -> [Double]? {
            guard let entry = ifd[tag], entry.type == 8 || entry.type == 3, entry.count >= 2, entry.count <= 64 else { return nil }
            let start = reader.dataStart(of: entry, offsetBase: 0)
            let values = (0..<entry.count).compactMap { reader.readInt16(at: start + $0 * 2) }
            guard values.count == entry.count, values[0] == entry.count - 1 else { return nil }
            return values.dropFirst().map(Double.init)
        }
        func radii(_ n: Int) -> [Double] { (0..<n).map { Double($0) / Double(max(n - 1, 1)) } }
        var correction = EmbeddedLensCorrection(unit: .halfDiagonal)
        if let d = knots(0x7037) {
            correction.distortion = RadialCurve(radii: radii(d.count), values: d.map { 1 + $0 * pow(2, -14) })
        }
        if let ca = knots(0x7035), ca.count % 2 == 0 {
            let half = ca.count / 2
            correction.red = RadialCurve(radii: radii(half), values: ca[0..<half].map { 1 + $0 * pow(2, -21) })
            correction.blue = RadialCurve(radii: radii(half), values: ca[half...].map { 1 + $0 * pow(2, -21) })
        }
        if let v = knots(0x7032) {
            correction.vignetting = RadialCurve(radii: radii(v.count), values: v.map { 1 / pow(2, 0.5 - pow(2, $0 * pow(2, -13) - 1)) })
        }
        return correction
    }

    /// Panasonic RW2 IFD0 0x0119, sixteen little-endian int16 (/32768):
    /// p02 at 2, p04 at 4, the scale at 5 (1 / (1 + v)), the on-flag in the
    /// low nibble of 7. Source radius over output: (1 + p02 r² + p04 r⁴) ·
    /// (1 + scale term), r in half long sides — the reading that matched the
    /// correction Apple's decoder applies from the same block.
    static func panasonic(_ block: [UInt8]) -> EmbeddedLensCorrection? {
        guard block.count >= 24 else { return nil }
        func value(_ index: Int) -> Double {
            Double(Int16(bitPattern: UInt16(block[index * 2]) | UInt16(block[index * 2 + 1]) << 8)) / 32768
        }
        let flag = Int(block[14]) & 0x0f
        guard flag != 0 else { return nil }
        let p02 = value(2), p04 = value(4), scale = 1 + value(5)
        let radii = stride(from: 0.0, through: 1.3, by: 0.02).map { $0 }
        return EmbeddedLensCorrection(
            unit: .halfLongSide,
            distortion: RadialCurve(radii: radii, values: radii.map { r in
                let r2 = r * r
                return (1 + p02 * r2 + p04 * r2 * r2) * scale
            })
        )
    }

    // MARK: Fujifilm RAF

    /// RAF: the FujiIFD the container points to holds 0xf00b distortion,
    /// 0xf00f CA and 0xf010 vignetting — signed rationals: an unused lead
    /// value, nine knot radii (half-diagonal units), then the values:
    /// distortion in percent, CA red then blue as offsets, vignetting as
    /// percent brightness.
    static func fujifilm(_ bytes: [UInt8]) -> EmbeddedLensCorrection? {
        // Offset directory: CFA header offset at 100 (big-endian).
        guard let offset = TIFFReader.readUInt32(bytes, at: 100, isLittleEndian: false),
              Int(offset) + 8 < bytes.count else { return nil }
        return fujiIFDs(bytes, from: Int(offset))
    }

    static func fujiIFDs(_ bytes: [UInt8], from start: Int) -> EmbeddedLensCorrection? {
        // The RAF raw section is a little-endian IFD chain wrapped in a
        // 0xf000 pointer; search a bounded window for the FujiIFD tags.
        let end = min(bytes.count - 12, start + 4096)
        guard start < end else { return nil }
        for position in stride(from: start, to: end, by: 2) {
            guard let reader = TIFFReader(bytes: bytes, base: position, isLittleEndian: true, firstIFDOffset: 0),
                  let count = reader.readUInt16(at: position), (8...64).contains(count),
                  let ifd = reader.ifd(atAbsolute: position, offsetBase: start),
                  ifd[0xf00b] != nil || ifd[0xf010] != nil
            else { continue }
            return fuji(ifd, reader: reader, offsetBase: start)
        }
        return nil
    }

    static func fuji(_ ifd: [Int: IFDEntry], reader: TIFFReader, offsetBase: Int) -> EmbeddedLensCorrection? {
        func rationals(_ tag: Int) -> [Double]? {
            guard let entry = ifd[tag], entry.type == 10, entry.count >= 19, entry.count <= 64 else { return nil }
            let start = reader.dataStart(of: entry, offsetBase: offsetBase)
            var out: [Double] = []
            for index in 0..<entry.count {
                guard let n = reader.readInt32(at: start + index * 8), let d = reader.readInt32(at: start + index * 8 + 4), d != 0
                else { return nil }
                out.append(Double(n) / Double(d))
            }
            return out
        }
        var correction = EmbeddedLensCorrection(unit: .halfDiagonal)
        if let d = rationals(0xf00b) {
            let radii = Array(d[1...9]), values = d[10...18].map { 1 + $0 / 100 }
            if values.contains(where: { abs($0 - 1) > 1e-9 }) { correction.distortion = RadialCurve(radii: radii, values: values) }
        }
        if let c = rationals(0xf00f), c.count >= 28 {
            let radii = Array(c[1...9])
            correction.red = RadialCurve(radii: radii, values: c[10...18].map { 1 + $0 })
            correction.blue = RadialCurve(radii: radii, values: c[19...27].map { 1 + $0 })
        }
        if let v = rationals(0xf010) {
            let radii = Array(v[1...9]), gains = v[10...18].map { $0 > 0 ? 100 / $0 : 1 }
            if gains.contains(where: { abs($0 - 1) > 1e-9 }) { correction.vignetting = RadialCurve(radii: radii, values: gains) }
        }
        return correction
    }

    // MARK: JPEG

    /// A Sony JPEG whose camera already corrected the lens: MakerNote 0x2013
    /// (DistortionCorrectionSetting) not 0 (16a §4). Nil when the file does
    /// not say.
    public static func isCorrectedInCamera(url: URL) -> Bool? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return isCorrectedInCamera(bytes: [UInt8](data.prefix(256 * 1024)))
    }

    public static func isCorrectedInCamera(bytes: [UInt8]) -> Bool? {
        guard let base = jpegTIFFBase(bytes), let reader = TIFFReader(bytes: bytes, base: base),
              let ifd0 = reader.ifd(atAbsolute: base + reader.firstIFDOffset, offsetBase: base),
              let make = ifd0[0x010f], let exifPointer = ifd0[0x8769],
              let exifOffset = reader.longValue(exifPointer, offsetBase: base),
              let exif = reader.ifd(atAbsolute: base + exifOffset, offsetBase: base),
              let note = exif[0x927c]
        else { return nil }
        let makeStart = reader.dataStart(of: make, offsetBase: base)
        let makeText = String(bytes: bytes[max(0, makeStart)..<min(bytes.count, makeStart + make.count)], encoding: .ascii) ?? ""
        guard makeText.uppercased().hasPrefix("SONY") else { return nil }
        let noteStart = reader.dataStart(of: note, offsetBase: base)
        // "SONY DSC \0\0\0" then an IFD whose offsets count from the TIFF base.
        let ifdStart = String(bytes: bytes[noteStart..<min(bytes.count, noteStart + 8)], encoding: .ascii) == "SONY DSC"
            ? noteStart + 12 : noteStart
        guard let sony = reader.ifd(atAbsolute: ifdStart, offsetBase: base), let setting = sony[0x2013],
              let value = reader.longValue(setting, offsetBase: base)
        else { return nil }
        return value != 0
    }

    static func jpegTIFFBase(_ bytes: [UInt8]) -> Int? {
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var i = 2
        while i + 10 < bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker == 0xE1, bytes[i + 4] == 0x45, bytes[i + 5] == 0x78, bytes[i + 6] == 0x69, bytes[i + 7] == 0x66 {
                return i + 10
            }
            if marker == 0xDA || length < 2 { return nil }
            i += 2 + length
        }
        return nil
    }
}

extension TIFFReader {
    /// An entry's bytes.
    func slice(_ entry: IFDEntry, offsetBase: Int) -> [UInt8] {
        let start = dataStart(of: entry, offsetBase: offsetBase)
        let size = entry.count * Self.typeSize(entry.type)
        guard start >= 0, size > 0, start + size <= bytes.count else { return [] }
        return Array(bytes[start..<(start + size)])
    }

    func readInt16(at offset: Int) -> Int? {
        readUInt16(at: offset).map { Int(Int16(bitPattern: UInt16($0))) }
    }

    func readInt32(at offset: Int) -> Int? {
        readUInt32(at: offset).map { Int(Int32(bitPattern: UInt32($0))) }
    }
}

/// Reads DNG opcode lists, which are big-endian whatever the file is.
struct BigEndianCursor {
    let bytes: [UInt8]
    var offset = 0

    mutating func uint32() -> UInt32? {
        guard let v = TIFFReader.readUInt32(bytes, at: offset, isLittleEndian: false) else { return nil }
        offset += 4
        return v
    }

    mutating func double() -> Double? {
        guard offset + 8 <= bytes.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits = bits << 8 | UInt64(bytes[offset + i]) }
        offset += 8
        return Double(bitPattern: bits)
    }
}
