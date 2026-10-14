import Foundation

/// A subtitle's name in the panel's menus (FS-23.03 §1): the language in
/// that language, then where it came from — `English · From Server`,
/// `Tiếng Việt · Translated (Claude)`.
enum MovieSubtitleLabel {
    /// - Parameters:
    ///   - fromFiles: the movie's source is a Files folder, not a server.
    ///   - providerName: who translated it, for a translated subtitle.
    static func title(_ subtitle: MovieSubtitle, fromFiles: Bool = false, providerName: String? = nil) -> String {
        "\(language(subtitle)) · \(origin(subtitle, fromFiles: fromFiles, providerName: providerName))"
    }

    static func language(_ subtitle: MovieSubtitle) -> String {
        if let code = MovieLanguage.code(subtitle.language), let name = MovieLanguage.endonym(code) { return name }
        return String(localized: "Unknown Language", comment: "Subtitle whose file says no language")
    }

    static func origin(_ subtitle: MovieSubtitle, fromFiles: Bool, providerName: String?) -> String {
        switch subtitle.origin {
        case .inFile:
            String(localized: "In File", comment: "Subtitle origin: a text track inside the movie file")
        case .sidecar:
            fromFiles
                ? String(localized: "From Files", comment: "Subtitle origin: a file next to the movie in a Files folder")
                : String(localized: "From Server", comment: "Subtitle origin: a file next to the movie on a server")
        case .plex:
            String(localized: "From Plex", comment: "Subtitle origin: a Plex subtitle")
        case .imported:
            String(localized: "Imported", comment: "Subtitle origin: picked with Import File…")
        case .shared:
            String(localized: "Shared", comment: "Subtitle origin: came through the Share sheet or AirDrop")
        case .translated:
            if let providerName {
                String(localized: "Translated (\(providerName))", comment: "Subtitle origin: made by AI translation, with the provider, e.g. Translated (Claude)")
            } else {
                String(localized: "Translated", comment: "Subtitle origin: made by AI translation")
            }
        }
    }

    /// `100% · White · +0.4 s` — the Style row's value.
    static func style(_ line: MovieSubtitleStyle.Line, offsetMs: Int) -> String {
        let size = (line.scale).formatted(.percent.precision(.fractionLength(0)))
        return "\(size) · \(colorName(line.color)) · \(sync(offsetMs))"
    }

    static func colorName(_ color: MovieSubtitleStyle.Color) -> String {
        switch color {
        case .white: String(localized: "White", comment: "Subtitle color")
        case .yellow: String(localized: "Yellow", comment: "Subtitle color")
        case .lightGray: String(localized: "Light Gray", comment: "Subtitle color")
        case .cyan: String(localized: "Cyan", comment: "Subtitle color")
        }
    }

    /// `0.0 s`, `+0.4 s`, `−2.0 s`.
    static func sync(_ ms: Int) -> String {
        let seconds = (Double(abs(ms)) / 1000).formatted(.number.precision(.fractionLength(1)))
        switch ms {
        case ..<0: return "\u{2212}\(seconds) s"
        case 0: return "\(seconds) s"
        default: return "+\(seconds) s"
        }
    }

    static func position(_ position: DualSubtitlePosition) -> String {
        switch position {
        case .primaryBottomSecondaryTop: String(localized: "Primary Bottom, Secondary Top", comment: "Subtitle position option")
        case .bothBottomSecondaryAbove: String(localized: "Both Bottom, Secondary Above", comment: "Subtitle position option")
        case .bothBottomSecondaryBelow: String(localized: "Both Bottom, Secondary Below", comment: "Subtitle position option")
        }
    }

    /// The Position row's value: `Secondary Above`.
    static func positionValue(_ position: DualSubtitlePosition) -> String {
        switch position {
        case .primaryBottomSecondaryTop: String(localized: "Secondary Top", comment: "Subtitle Position row value")
        case .bothBottomSecondaryAbove: String(localized: "Secondary Above", comment: "Subtitle Position row value")
        case .bothBottomSecondaryBelow: String(localized: "Secondary Below", comment: "Subtitle Position row value")
        }
    }
}
