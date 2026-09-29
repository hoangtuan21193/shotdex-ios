import Foundation
import ShotDexKit

/// A tile of the Presets panel as a look that can leave the phone (FS-03.14c):
/// one of the user's looks, a built-in film look, or an imported LUT.
enum LookExportSource {
    case look(LookPreset)
    case preset(PhotoFilter, name: String)
    case lut(id: String, name: String, url: URL)

    var name: String {
        switch self {
        case let .look(look): look.name
        case let .preset(_, name): name
        case let .lut(_, name, _): name
        }
    }

    /// The look this tile stands for.
    var preset: LookPreset {
        switch self {
        case let .look(look):
            return look
        case let .preset(filter, name):
            var recipe = PhotoEditRecipe.identity
            recipe.filter = filter
            return LookPreset(name: name, recipe: recipe)
        case let .lut(id, name, _):
            var recipe = PhotoEditRecipe.identity
            recipe.lutID = id
            return LookPreset(name: name, recipe: recipe)
        }
    }
}

enum LookExport {
    /// A file name from a look's name: the characters a file system refuses
    /// replaced, never empty (14c §1).
    static func fileName(_ name: String, pathExtension: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        var cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.hasPrefix(".") { cleaned = "Look" + cleaned }
        return "\(cleaned).\(pathExtension)"
    }

    /// A `.shotdexlook` for `source` in a fresh temporary folder, ready for
    /// the share sheet — exactly one file, no image (14c §2). `lutText` reads
    /// an imported LUT's `.cube` when the look points at one.
    static func shotdexLookFile(for source: LookExportSource, lutText: (String) -> (name: String, text: String)?) throws -> URL {
        let preset = source.preset
        let embedded = preset.recipe.lutID.flatMap(lutText).map { LookFile.EmbeddedLUT(name: $0.name, cube: $0.text) }
        let data = try LookFileCodec.encode(preset, lut: embedded)
        return try write(data, name: source.name, pathExtension: LookFileCodec.pathExtension)
    }

    static func write(_ data: Data, name: String, pathExtension: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(name, pathExtension: pathExtension))
        try data.write(to: url, options: .atomic)
        return url
    }
}
