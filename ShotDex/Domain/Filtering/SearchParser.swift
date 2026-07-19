import Foundation

/// Structured interpretation of a free-text search query.
/// Recognized tokens: `ISO 3200` / `iso3200`, `f/1.8` / `F1.8`, `1/500` /
/// `1/500s`, `85mm`, sensor format names. Bare numbers are ORed into
/// ISO / focal length / device names. Everything else is free text matched
/// against camera and lens models.
struct ParsedSearch: Equatable, Sendable {
    var iso: Int?
    var aperture: Double?
    var shutterSeconds: Double?
    var focalLength: Double?
    var sensorFormat: SensorFormat?
    var bareNumbers: [Double] = []
    var freeTextTerms: [String] = []

    var isEmpty: Bool {
        iso == nil && aperture == nil && shutterSeconds == nil && focalLength == nil
            && sensorFormat == nil && bareNumbers.isEmpty && freeTextTerms.isEmpty
    }
}

/// Pure Swift query DSL parser for Library search.
enum SearchParser {

    private static let sensorFormatAliases: [String: SensorFormat] = [
        "full frame": .fullFrame,
        "fullframe": .fullFrame,
        "ff": .fullFrame,
        "aps-h": .apsH,
        "apsh": .apsH,
        "aps-c": .apsC,
        "apsc": .apsC,
        "micro four thirds": .microFourThirds,
        "mft": .microFourThirds,
        "m43": .microFourThirds,
        "m4/3": .microFourThirds,
        "1-inch": .oneInch,
        "1 inch": .oneInch,
        "medium format": .mediumFormat,
        "smartphone": .smartphone,
        "compact": .compact,
    ]

    static func parse(_ query: String) -> ParsedSearch {
        var result = ParsedSearch()
        var pendingISO = false
        var remaining = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return result }

        // Multi-word sensor format names first, so their words don't leak
        // into free text.
        let lowered = remaining.lowercased()
        for (alias, format) in sensorFormatAliases.sorted(by: { $0.key.count > $1.key.count })
        where alias.contains(" ") || alias.contains("-") {
            if lowered.contains(alias) {
                result.sensorFormat = format
                remaining = remaining.replacingOccurrences(of: alias, with: " ", options: [.caseInsensitive])
                break
            }
        }

        for token in remaining.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let token = String(token)
            let lower = token.lowercased()

            // ISO with attached or following value is handled below via "iso3200";
            // the standalone word "iso" is dropped and its number captured
            // when glued. "ISO 3200" arrives as two tokens: "iso" + bare 3200 —
            // treat a bare number after "iso" as ISO.
            if lower == "iso" {
                pendingISO = true
                continue
            }
            if let match = lower.wholeMatch(of: /iso(\d+)/), let value = Int(match.1) {
                result.iso = value
                continue
            }
            if let match = lower.wholeMatch(of: /f\/?(\d+(?:\.\d+)?)/), let value = Double(match.1) {
                result.aperture = value
                continue
            }
            if let match = lower.wholeMatch(of: /1\/(\d+(?:\.\d+)?)s?/), let value = Double(match.1), value > 0 {
                result.shutterSeconds = 1.0 / value
                continue
            }
            if let match = lower.wholeMatch(of: /(\d+(?:\.\d+)?)s/), let value = Double(match.1), lowerLooksLikeShutter(lower) {
                result.shutterSeconds = value
                continue
            }
            if let match = lower.wholeMatch(of: /(\d+(?:\.\d+)?)mm/), let value = Double(match.1) {
                result.focalLength = value
                continue
            }
            if let format = sensorFormatAliases[lower] {
                result.sensorFormat = format
                continue
            }
            if let number = Double(lower) {
                if pendingISO {
                    result.iso = Int(number)
                    pendingISO = false
                } else {
                    result.bareNumbers.append(number)
                }
                continue
            }
            result.freeTextTerms.append(token)
        }
        return result
    }

    /// "2s"-style long exposures; avoids treating "50s" (as in "ISO 50s" typo)
    /// weirdly — only accept small values as whole-second shutters.
    private static func lowerLooksLikeShutter(_ token: String) -> Bool {
        guard let match = token.wholeMatch(of: /(\d+(?:\.\d+)?)s/), let value = Double(match.1) else { return false }
        return value <= 60
    }
}
