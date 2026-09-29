import Foundation
import ShotDexKit

/// One setting of a look, by name — what an imported look records it set
/// (FS-03.14b §1, E6) so applying it changes only those.
struct LookSettingKey: RawRepresentable, Hashable, Codable, Sendable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static func adjustment(_ kind: PhotoAdjustmentKind) -> LookSettingKey { .init(rawValue: "adjustment.\(kind.rawValue)") }
    static func mixer(_ band: ColorMixerBand, _ property: ColorMixerProperty) -> LookSettingKey {
        .init(rawValue: "mixer.\(band.rawValue).\(property.rawValue)")
    }
}

/// A line of the import report under a preset (FS-03.14a §3).
struct PresetReportLine: Equatable, Sendable {
    enum Kind: Sendable { case applied, changed, skipped }
    var kind: Kind
    var text: String

    /// What VoiceOver reads before the text — the status is never only a glyph.
    var symbol: String {
        switch kind {
        case .applied: "✓"
        case .changed: "≈"
        case .skipped: "✕"
        }
    }
}

struct LightroomMappingResult: Equatable {
    var recipe = PhotoEditRecipe.identity
    var namedSettings: Set<LookSettingKey> = []
    /// Lines worth showing: changes and skips. Applied settings are counted,
    /// not listed.
    var lines: [PresetReportLine] = []
    var appliedCount = 0
}

/// Lightroom `crs:` settings → a ShotDex look (FS-03.14b). The numbers live in
/// `LightroomMappingTable`; this walks a preset's tags through it.
enum LightroomMapping {
    static func map(_ settings: LightroomSettings) -> LightroomMappingResult {
        var result = LightroomMappingResult()
        for tag in settings.values.keys.sorted() {
            guard let raw = settings.values[tag] else { continue }
            if LightroomMappingTable.administrative.contains(tag) { continue }
            if let row = LightroomMappingTable.adjustments[tag] {
                apply(row, tag: tag, raw: raw, to: &result)
            } else if let target = LightroomMappingTable.mixerTarget(tag) {
                applyMixer(target, raw: raw, to: &result)
            } else {
                result.lines.append(.init(kind: .changed, text: "Unknown setting \(tag) — ignored"))
            }
        }
        return result
    }

    private static func number(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: ""))
    }

    private static func apply(_ row: LightroomMappingTable.AdjustmentRow, tag: String, raw: String, to result: inout LightroomMappingResult) {
        guard let value = number(raw) else {
            result.lines.append(.init(kind: .skipped, text: "\(row.title) value “\(raw)” isn't a number — ignored"))
            return
        }
        let mapped = row.map(value)
        let range = row.kind.range
        let clamped = min(range.upperBound, max(range.lowerBound, mapped))
        result.recipe.adjustments[row.kind] = clamped
        result.namedSettings.insert(.adjustment(row.kind))
        result.appliedCount += 1
        if clamped != mapped {
            result.lines.append(.init(kind: .changed, text: row.clampedText(original: value, set: clamped)))
        }
    }

    private static func applyMixer(_ target: (ColorMixerBand, ColorMixerProperty), raw: String, to result: inout LightroomMappingResult) {
        guard let value = number(raw) else { return }
        let (band, property) = target
        var channel = result.recipe.color.mixer[band]
        channel[property] = min(1, max(-1, value / 100))
        result.recipe.color.mixer[band] = channel
        result.namedSettings.insert(.mixer(band, property))
        result.appliedCount += 1
    }
}
