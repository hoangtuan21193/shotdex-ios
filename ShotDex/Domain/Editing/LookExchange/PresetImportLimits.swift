import Foundation

/// FS-03.14a §2 as data: how large a file may be before its content is read,
/// checked against the size the file system reports, never by opening it.
enum PresetImportLimits {
    enum Kind: Equatable {
        case xmp, lrtemplate, shotdexlook, dng, cube

        init?(pathExtension: String) {
            switch pathExtension.lowercased() {
            case "xmp": self = .xmp
            case "lrtemplate": self = .lrtemplate
            case "shotdexlook": self = .shotdexlook
            case "dng": self = .dng
            case "cube": self = .cube
            default: return nil
            }
        }

        var maximumBytes: Int {
            switch self {
            case .xmp, .lrtemplate: 5 * megabyte
            // A look embedding a 64³ LUT as .cube text is about 6.5 MB; the
            // same ceiling holds for a .cube itself.
            case .shotdexlook, .cube: 16 * megabyte
            case .dng: 200 * megabyte
            }
        }
    }

    static let megabyte = 1_000_000
    /// Presets in one import; the rest are ✕ "Import the rest separately".
    static let maximumPresetsPerImport = 500

    enum Refusal: Error, Equatable {
        case notAPreset
        case tooLarge(limitMegabytes: Int)
        case unreadable

        var message: String {
            switch self {
            case .notAPreset: "Not a preset ShotDex can read"
            case let .tooLarge(limit): "Larger than \(limit) MB — not a preset"
            case .unreadable: "The file couldn't be read"
            }
        }
    }

    /// The kind of `url`, or why it will not be read — before a byte of it is.
    static func check(_ url: URL) -> Result<Kind, Refusal> {
        guard let kind = Kind(pathExtension: url.pathExtension) else { return .failure(.notAPreset) }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return .failure(.unreadable) }
        guard size <= kind.maximumBytes else { return .failure(.tooLarge(limitMegabytes: kind.maximumBytes / megabyte)) }
        return .success(kind)
    }
}
