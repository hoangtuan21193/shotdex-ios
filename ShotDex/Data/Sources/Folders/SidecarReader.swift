import CryptoKit
import Foundation
import ImageIO

/// What a `.xmp` sidecar says about a photo (FS-19.02 §4) — the fields
/// ShotDex reads, nothing else. Develop settings are not read here: Import
/// Lightroom Edits reads them on command (FS-03.14b).
struct SidecarValues: Equatable, Sendable {
    /// The photo's stars, 0–5: the standard `xmp:Rating`, or — while it says
    /// Reject — the stars ShotDex keeps in its own namespace.
    var rating: Int?
    /// `xmp:Rating` = −1, the way Lightroom and Bridge write Reject.
    var isRejected = false
    var keywords: [String] = []
    var title: String?
    var caption: String?
    /// ShotDex's namespace: Pick, favorite and the edit recipe — fields
    /// other apps skip (FS-19.02 §5).
    var isPicked = false
    var isFavorite: Bool?
    var recipe: Data?

    var isEmpty: Bool { self == SidecarValues() }
}

/// Reads `.xmp` sidecars with ImageIO's XMP parser. Never writes.
enum SidecarReader {
    /// The two names a sidecar of `relativePath` goes by — `DSC0001.xmp`
    /// (Lightroom, Capture One, Bridge) and `DSC0001.ARW.xmp` — as path keys;
    /// only the second for a JPEG whose RAW keeps the first.
    static func candidateKeys(for relativePath: String, fullNameOnly: Bool = false, pathKey: (String) -> String) -> [String] {
        let base = (relativePath as NSString).deletingPathExtension
        return fullNameOnly ? [pathKey(relativePath + ".xmp")] : [pathKey(base + ".xmp"), pathKey(relativePath + ".xmp")]
    }

    /// The sidecar of a photo among the sidecars a listing found: the newer
    /// of its two names when both are there (FS-19.02 §4).
    static func sidecar<Entry>(for relativePaths: [String], fullNameOnly: Bool = false, in sidecars: [String: Entry],
                               modified: (Entry) -> Date?, pathKey: (String) -> String) -> Entry? {
        relativePaths
            .flatMap { candidateKeys(for: $0, fullNameOnly: fullNameOnly, pathKey: pathKey) }
            .compactMap { sidecars[$0] }
            .max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    /// What a file says about itself in its own XMP — a camera's stars
    /// (Sony, Fuji), or what an app wrote into a JPEG. Only for file photos:
    /// a Photos asset takes its stars from Photos (FS-01.12 §7).
    static func embedded(in source: CGImageSource) -> SidecarValues? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return nil }
        let values = values(metadata)
        return values.isEmpty ? nil : values
    }

    /// A sidecar beats the file's own XMP field by field; keywords from both
    /// are kept (FS-19.02 §4).
    static func combined(embedded: SidecarValues?, sidecar: SidecarValues?) -> SidecarValues? {
        guard let sidecar else { return embedded }
        guard let embedded else { return sidecar }
        var out = sidecar
        let sidecarSaysStars = sidecar.rating != nil || sidecar.isRejected
        if !sidecarSaysStars {
            out.rating = embedded.rating
            out.isRejected = embedded.isRejected
        }
        var seen = Set(out.keywords.map(KeywordInput.caseKey))
        out.keywords += embedded.keywords.filter { seen.insert(KeywordInput.caseKey($0)).inserted }
        out.title = sidecar.title ?? embedded.title
        out.caption = sidecar.caption ?? embedded.caption
        out.isFavorite = sidecar.isFavorite ?? embedded.isFavorite
        out.recipe = sidecar.recipe ?? embedded.recipe
        return out
    }

    /// What ShotDex remembers of a sidecar it read or wrote: its
    /// modification time and a hash of its bytes (FS-19.02 §6). A different
    /// stamp before a write means another app wrote it since.
    static func stamp(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return stamp(of: data, modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    /// The same stamp from bytes already read — a sidecar on a server.
    static func stamp(of data: Data, modified: Date?) -> String {
        let digest = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(Int((modified ?? .distantPast).timeIntervalSince1970)):\(digest)"
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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
        let own = shotdexFields(metadata)
        if let text = string(metadata, "xmp:Rating"), let stars = Int(text.trimmingCharacters(in: .whitespaces)) {
            if stars < 0 {
                values.isRejected = true
                values.rating = own["Rating"].flatMap { Int($0) }.map { min(max($0, 0), 5) }
            } else {
                values.rating = min(stars, 5)
            }
        }
        values.keywords = strings(metadata, "dc:subject")
        values.title = strings(metadata, "dc:title").first
        values.caption = strings(metadata, "dc:description").first
        values.isPicked = own["Flag"] == PhotoFlag.pick.rawValue && !values.isRejected
        values.isFavorite = own["Favorite"].map { $0.lowercased() == "true" }
        values.recipe = own["Recipe"].flatMap { Data(base64Encoded: $0) }
        return values
    }

    /// Simple properties in ShotDex's namespace, by local name — found by
    /// namespace, whatever prefix the file bound it to.
    private static func shotdexFields(_ metadata: CGImageMetadata) -> [String: String] {
        final class Fields { var values: [String: String] = [:] }
        let fields = Fields()
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { _, tag in
            if CGImageMetadataTagCopyNamespace(tag) as String? == XMPPatcher.shotdexNamespace,
               let name = CGImageMetadataTagCopyName(tag) as String?,
               let value = CGImageMetadataTagCopyValue(tag) as? String {
                fields.values[name] = value
            }
            return true
        }
        return fields.values
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
