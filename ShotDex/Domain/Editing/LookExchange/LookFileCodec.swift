import Foundation
import ShotDexKit

/// A `.shotdexlook` file (FS-03.14c §1): one look, as UTF-8 JSON — the format
/// id, schema version 1, the name, where it came from, when, the whole look
/// cut and, when the look points at an imported LUT, that LUT's `.cube` text.
/// Never an image: the receiving phone renders its own tile (§2).
struct LookFile: Codable, Equatable {
    var format: String
    var schemaVersion: Int
    var name: String
    var source: LookSource
    var createdAt: Date
    var look: PhotoEditRecipe
    var lut: EmbeddedLUT?

    struct EmbeddedLUT: Codable, Equatable {
        var name: String
        var cube: String
    }
}

/// Why a `.shotdexlook` did not come in — the report's ✕ line.
enum LookFileError: Error, Equatable {
    case notALook
    case newerSchema

    var message: String {
        switch self {
        case .notALook: "This file isn't a ShotDex look."
        case .newerSchema: "Made with a newer ShotDex — update the app to add it"
        }
    }
}

enum LookFileCodec {
    static let format = "com.hoangtuan.shotdex.look"
    static let schemaVersion = 1
    static let pathExtension = "shotdexlook"

    /// The file for `preset`; `lut` is the text and name of the imported
    /// LUT its recipe points at, if any.
    static func encode(_ preset: LookPreset, lut: LookFile.EmbeddedLUT? = nil) throws -> Data {
        let file = LookFile(
            format: format,
            schemaVersion: schemaVersion,
            name: preset.name,
            source: preset.source,
            createdAt: preset.createdAt,
            look: EditorSyncScope.look.apply(preset.recipe, onto: .identity),
            lut: preset.recipe.lutID == nil ? nil : lut
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// Reads a file, refusing one from a newer schema before anything else
    /// in it is trusted.
    static func decode(_ data: Data) throws(LookFileError) -> LookFile {
        struct Header: Decodable {
            var format: String
            var schemaVersion: Int
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw .notALook
        }
        guard header.schemaVersion <= schemaVersion else { throw .newerSchema }
        guard let file = try? decoder.decode(LookFile.self, from: data) else { throw .notALook }
        return file
    }
}
