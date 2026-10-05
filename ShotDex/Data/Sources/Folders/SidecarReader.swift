import Foundation
import ImageIO

/// What a `.xmp` sidecar says about a photo (FS-19.02 §4) — the fields
/// ShotDex reads, nothing else. Develop settings are not read here: Import
/// Lightroom Edits reads them on command (FS-03.14b).
struct SidecarValues: Equatable, Sendable {
    /// 0–5 from the standard `xmp:Rating`; nil when the field is absent or
    /// says Reject.
    var rating: Int?
    /// `xmp:Rating` = −1, the way Lightroom and Bridge write Reject.
    var isRejected = false
    var keywords: [String] = []
    var title: String?
    var caption: String?

    var isEmpty: Bool { self == SidecarValues() }
}

/// Reads `.xmp` sidecars with ImageIO's XMP parser. Never writes.
enum SidecarReader {
    /// The two names a sidecar of `relativePath` goes by — `DSC0001.xmp`
    /// (Lightroom, Capture One, Bridge) and `DSC0001.ARW.xmp` — as path keys.
    static func candidateKeys(for relativePath: String, pathKey: (String) -> String) -> [String] {
        let base = (relativePath as NSString).deletingPathExtension
        return [pathKey(base + ".xmp"), pathKey(relativePath + ".xmp")]
    }

    /// The sidecar of a photo among the sidecars a listing found: the newer
    /// of its two names when both are there (FS-19.02 §4).
    static func sidecar<Entry>(for relativePaths: [String], in sidecars: [String: Entry],
                               modified: (Entry) -> Date?, pathKey: (String) -> String) -> Entry? {
        relativePaths
            .flatMap { candidateKeys(for: $0, pathKey: pathKey) }
            .compactMap { sidecars[$0] }
            .max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    static func read(sidecarAt url: URL) -> SidecarValues? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return values(xmp: data)
    }

    static func values(xmp data: Data) -> SidecarValues? {
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else { return nil }
        return values(metadata)
    }

    static func values(_ metadata: CGImageMetadata) -> SidecarValues {
        var values = SidecarValues()
        if let text = string(metadata, "xmp:Rating"), let stars = Int(text.trimmingCharacters(in: .whitespaces)) {
            if stars < 0 {
                values.isRejected = true
            } else {
                values.rating = min(stars, 5)
            }
        }
        values.keywords = strings(metadata, "dc:subject")
        values.title = strings(metadata, "dc:title").first
        values.caption = strings(metadata, "dc:description").first
        return values
    }

    private static func string(_ metadata: CGImageMetadata, _ path: String) -> String? {
        CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
    }

    /// A bag, a sequence or a language alternative as its plain strings; a
    /// simple value as one string. Blank entries are dropped.
    private static func strings(_ metadata: CGImageMetadata, _ path: String) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag) else { return [] }
        let items: [Any] = (value as? [Any]) ?? [value]
        return items.compactMap { item -> String? in
            if CFGetTypeID(item as CFTypeRef) == CGImageMetadataTagGetTypeID() {
                return CGImageMetadataTagCopyValue(item as! CGImageMetadataTag) as? String
            }
            return item as? String
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
}
