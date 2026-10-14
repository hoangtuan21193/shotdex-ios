import Foundation

/// How a movie's two subtitles look (FS-23.03 §2): where they sit, and size
/// and color per line. Stored as JSON on `movie_subtitle_choices.style`,
/// read leniently — an unknown or missing field keeps its default.
struct MovieSubtitleStyle: Codable, Equatable, Sendable {
    /// Content colors, not interface tokens (FS-23.03 §2).
    enum Color: String, Codable, CaseIterable, Sendable {
        case white, yellow, lightGray, cyan
    }

    struct Line: Codable, Equatable, Sendable {
        /// 0.5…2.0 = 50…200 %.
        var scale: Double
        var color: Color

        static let scaleRange = 0.5...2.0
    }

    var position: DualSubtitlePosition = .bothBottomSecondaryAbove
    var primary = Line(scale: 1, color: .white)
    var secondary = Line(scale: 0.85, color: .yellow)

    private enum CodingKeys: String, CodingKey {
        case position, primary, secondary
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MovieSubtitleStyle()
        position = (try? container.decodeIfPresent(DualSubtitlePosition.self, forKey: .position)) ?? defaults.position
        primary = Self.line(container, .primary) ?? defaults.primary
        secondary = Self.line(container, .secondary) ?? defaults.secondary
    }

    private static func line(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Line? {
        guard let line = try? container.decodeIfPresent(Line.self, forKey: key) else { return nil }
        return Line(scale: min(max(line.scale, Line.scaleRange.lowerBound), Line.scaleRange.upperBound), color: line.color)
    }

    static func decode(_ json: String) -> MovieSubtitleStyle {
        (try? JSONDecoder().decode(MovieSubtitleStyle.self, from: Data(json.utf8))) ?? MovieSubtitleStyle()
    }

    var json: String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}"
    }
}
