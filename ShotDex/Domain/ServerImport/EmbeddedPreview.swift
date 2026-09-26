import CoreGraphics
import Foundation
import ImageIO

/// Pulls a thumbnail out of the head of an image file — the embedded JPEG
/// previews cameras write into RAW files, or a JPEG/HEIC's EXIF thumbnail
/// (FS-17.01 §3).
///
/// Measured on one file per maker (2026-09-26, raw.pixls.us samples + a
/// Canon R6 II CR3): NEF, PEF and Pentax DNG carry a ≥ 640 px JPEG inside
/// 256 KB; CR3 needs 512 KB (its `PRVW` box — ImageIO cannot read a CR3 head
/// at all); RW2, ORF and ARW need 1 MB; RAF keeps a full-size JPEG behind a
/// pointer in its header; an iPhone ProRAW DNG has no embedded JPEG but
/// ImageIO thumbnails its head directly.
enum EmbeddedPreview {
    /// The first read, and the longer one when that did not give a sharp
    /// enough preview.
    static let firstRead = 256 * 1024
    static let secondRead = 1024 * 1024
    /// Below this the preview is blurry on a grid tile; keep looking.
    static let sharpEnough = 320
    /// What a tile is drawn from.
    static let maxPixelSize = 400
    /// RAF previews are full-size JPEGs; beyond this, the tile makes do.
    static let rafPreviewLimit = 8 * 1024 * 1024

    struct Thumbnail: @unchecked Sendable {
        let image: CGImage
        /// Long side of the preview it was made from — or, when ImageIO made
        /// the thumbnail itself, of that thumbnail (≤ `maxPixelSize`). Only
        /// compared against `sharpEnough` and against other candidates.
        let sourceLongSide: Int
    }

    /// The best preview in `head`: ImageIO's own thumbnail when it has one,
    /// else the smallest embedded JPEG that is sharp enough (cheapest to
    /// decode), else the largest there is.
    static func thumbnail(from head: Data) -> Thumbnail? {
        var best: Thumbnail?
        if let fromImageIO = imageIOThumbnail(head) {
            best = fromImageIO
            if fromImageIO.sourceLongSide >= sharpEnough { return fromImageIO }
        }
        let spans = embeddedJPEGs(in: head)
        let pick = spans.filter { $0.longSide >= sharpEnough }.min { $0.longSide < $1.longSide }
            ?? spans.max { $0.longSide < $1.longSide }
        if let pick, pick.longSide > (best?.sourceLongSide ?? 0),
           let image = decode(head.subdata(in: pick.range)) {
            best = Thumbnail(image: image, sourceLongSide: pick.longSide)
        }
        return best
    }

    /// A whole small file (a PNG, or a JPEG whose EXIF thumbnail is 160 px).
    static func thumbnail(ofFileAt url: URL) -> Thumbnail? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longSide = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? image.width,
                           properties?[kCGImagePropertyPixelHeight] as? Int ?? image.height)
        return Thumbnail(image: image, sourceLongSide: longSide)
    }

    /// The date the photo was taken, from the EXIF in the head of the file —
    /// Date Taken sorting (FS-17.01 §2). `OffsetTimeOriginal` when written,
    /// else the device's time zone, the way the camera's clock was set.
    ///
    /// ImageIO reads the EXIF of a JPEG, HEIC, NEF or DNG head but not of a
    /// CR3, RAF, PEF, ARW or RW2 head; for those the first EXIF date string in
    /// the head is used — cameras write DateTime and DateTimeOriginal as the
    /// same 20-byte string, and it was the capture time in every sample file.
    static func captureDate(from head: Data, timeZone: TimeZone = .current) -> Date? {
        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, head as CFData, false)
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let date = captureDate(fromEXIF: exif, timeZone: timeZone) {
            return date
        }
        return firstEXIFDateString(in: head).flatMap { parseEXIFDate($0, timeZone: timeZone) }
    }

    /// `DateTimeOriginal` of an EXIF dictionary, with its offset when written.
    static func captureDate(fromEXIF exif: [CFString: Any], timeZone: TimeZone = .current) -> Date? {
        guard let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssZZZZZ"
            if let date = formatter.date(from: original + offset) { return date }
        }
        return parseEXIFDate(original, timeZone: timeZone)
    }

    static func parseEXIFDate(_ text: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter.date(from: text)
    }

    /// `2022:10:10 16:23:07` followed by its NUL terminator, the way EXIF
    /// stores an ASCII date.
    static func firstEXIFDateString(in data: Data) -> String? {
        let bytes = [UInt8](data)
        let pattern: [Character] = Array("dddd:dd:dd dd:dd:dd")
        guard bytes.count > pattern.count else { return nil }
        outer: for start in 0..<(bytes.count - pattern.count) {
            guard bytes[start + pattern.count] == 0 else { continue }
            for (offset, expected) in pattern.enumerated() {
                let byte = bytes[start + offset]
                switch expected {
                case "d": if !(0x30...0x39).contains(byte) { continue outer }
                default: if byte != expected.asciiValue { continue outer }
                }
            }
            return String(decoding: bytes[start..<(start + pattern.count)], as: UTF8.self)
        }
        return nil
    }

    /// Where a RAF keeps its preview JPEG: offset and length, big-endian, at
    /// bytes 84–91 after the `FUJIFILMCCD-RAW` magic.
    static func rafPreviewRange(header: Data) -> (offset: Int64, length: Int)? {
        let bytes = [UInt8](header.prefix(92))
        guard bytes.count >= 92, String(decoding: bytes[0..<15], as: UTF8.self) == "FUJIFILMCCD-RAW" else { return nil }
        func word(_ at: Int) -> Int { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        let offset = word(84), length = word(88)
        guard offset > 0, length > 0 else { return nil }
        return (Int64(offset), length)
    }

    // MARK: JPEG spans

    struct JPEGSpan: Equatable {
        let range: Range<Int>
        let longSide: Int
    }

    /// Complete JPEGs in `data`: a start marker whose end marker is also
    /// inside `data`. ImageIO calls a cut-off JPEG "complete" once it has read
    /// the header, so the end is found by walking the markers ourselves —
    /// which also steps over the EXIF thumbnail nested in a JPEG's APP1.
    static func embeddedJPEGs(in data: Data, limit: Int = 16) -> [JPEGSpan] {
        let bytes = [UInt8](data)
        var spans: [JPEGSpan] = []
        var index = 0
        while index + 3 < bytes.count, spans.count < limit {
            if bytes[index] == 0xFF, bytes[index + 1] == 0xD8, bytes[index + 2] == 0xFF,
               let end = jpegEnd(bytes, from: index) {
                if let longSide = pixelLongSide(data.subdata(in: index..<end)) {
                    spans.append(JPEGSpan(range: index..<end, longSide: longSide))
                }
                index = end
                continue
            }
            index += 1
        }
        return spans
    }

    /// One past the end marker of the JPEG starting at `start`, or nil when
    /// the JPEG runs past the buffer.
    static func jpegEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start + 2
        // `+ 1`, not `+ 3`: the end marker is two bytes and may be the last
        // two of the buffer — a RAF preview read by its exact length is.
        while index + 1 < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            if marker == 0xFF { index += 1; continue }                 // fill byte
            if marker == 0xD9 { return index + 2 }                      // end of image
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { index += 2; continue }
            guard index + 3 < bytes.count else { return nil }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2 else { return nil }
            if marker == 0xDA {
                // Entropy-coded data: runs to the next marker that is not a
                // stuffed 0x00, a restart marker or a fill byte.
                var scan = index + 2 + length
                var next: Int?
                while scan + 1 < bytes.count {
                    if bytes[scan] == 0xFF {
                        let following = bytes[scan + 1]
                        if following != 0x00, following != 0xFF, !(0xD0...0xD7).contains(following) {
                            next = scan
                            break
                        }
                    }
                    scan += 1
                }
                guard let next else { return nil }
                index = next
                continue
            }
            index += 2 + length
        }
        return nil
    }

    // MARK: ImageIO

    private static func imageIOThumbnail(_ head: Data) -> Thumbnail? {
        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, head as CFData, false)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Thumbnail(image: image, sourceLongSide: max(image.width, image.height))
    }

    private static func pixelLongSide(_ jpeg: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }

    private static func decode(_ jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
