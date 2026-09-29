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
    static func grayMixer(_ band: ColorMixerBand) -> LookSettingKey { .init(rawValue: "grayMixer.\(band.rawValue)") }
    static func calibration(_ key: String) -> LookSettingKey { .init(rawValue: "calibration.\(key)") }
    static func grading(_ region: ColorGradingRegion, _ part: String) -> LookSettingKey {
        .init(rawValue: "grading.\(region.rawValue).\(part)")
    }
    static let gradingBlending = LookSettingKey(rawValue: "grading.blending")
    static let gradingBalance = LookSettingKey(rawValue: "grading.balance")
    static func region(_ key: String) -> LookSettingKey { .init(rawValue: "curve.region.\(key)") }
    static func curve(_ channel: ToneCurveChannel) -> LookSettingKey { .init(rawValue: "curve.\(channel.rawValue)") }
    static let vignetteStyle = LookSettingKey(rawValue: "vignetteStyle")
    static let filter = LookSettingKey(rawValue: "filter")
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
        var skippedGroups: [String] = []
        func skip(_ group: LightroomMappingTable.SkippedGroup) {
            guard !skippedGroups.contains(group.message) else { return }
            skippedGroups.append(group.message)
        }
        // Nested structures first: a mask group carries Exposure of its own,
        // which must never reach the look (D37) — it is skipped whole.
        for tag in settings.structures.sorted() {
            if let group = LightroomMappingTable.skippedGroup(for: tag) { skip(group) }
        }
        for tag in settings.values.keys.sorted() {
            guard let raw = settings.values[tag] else { continue }
            if LightroomMappingTable.administrative.contains(tag) { continue }
            if let group = LightroomMappingTable.skippedGroup(for: tag) {
                skip(group)
            } else if LightroomMappingTable.legacyProcess.contains(tag) {
                skip(.init(message: "Settings from Lightroom 3 or older") { _ in false })
            } else if let message = LightroomMappingTable.notInShotDex[tag] {
                result.lines.append(.init(kind: .skipped, text: message))
            } else if let row = LightroomMappingTable.adjustments[tag] {
                apply(row, tag: tag, raw: raw, to: &result)
            } else if let target = LightroomMappingTable.mixerTarget(tag) {
                applyMixer(target, raw: raw, to: &result)
            } else if let target = LightroomMappingTable.structuredTarget(tag) {
                applyStructured(target, raw: raw, to: &result)
            } else if let special = applySpecial(tag, raw: raw, to: &result), special {
                continue
            } else {
                result.lines.append(.init(kind: .changed, text: "Unknown setting \(tag) — ignored"))
            }
        }
        for tag in settings.lists.keys.sorted() {
            guard let points = settings.lists[tag] else { continue }
            if let channel = LightroomMappingTable.curveLists[tag] {
                applyCurve(channel, points: points, to: &result)
            } else if let message = LightroomMappingTable.notInShotDex[tag] {
                result.lines.append(.init(kind: .skipped, text: message))
            }
        }
        result.lines += skippedGroups.map { PresetReportLine(kind: .skipped, text: $0) }
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

    /// Settings with a rule of their own: switches and pickers.
    private static func applySpecial(_ tag: String, raw: String, to result: inout LightroomMappingResult) -> Bool? {
        switch tag {
        case "ConvertToGrayscale":
            let isOn = raw.lowercased() == "true"
            result.recipe.adjustments[.blackAndWhite] = isOn ? 1 : 0
            result.namedSettings.insert(.adjustment(.blackAndWhite))
            result.appliedCount += 1
            return true
        case "LensProfileEnable":
            let isOn = raw == "1"
            result.recipe.adjustments[.lensCorrection] = isOn ? 1 : 0
            result.namedSettings.insert(.adjustment(.lensCorrection))
            result.appliedCount += 1
            if isOn {
                result.lines.append(.init(kind: .changed, text: "Lens correction on — the lens is chosen by ShotDex"))
            }
            return true
        case "CameraProfile":
            switch CameraProfileMap.match(raw) {
            case let .exact(filter):
                result.recipe.filter = filter
            case let .near(filter):
                result.recipe.filter = filter
                result.lines.append(.init(kind: .changed, text: "Profile '\(raw)' — ShotDex look \(filter.displayName) used"))
            case .none:
                result.recipe.filter = .original
                result.lines.append(.init(kind: .changed, text: "No ShotDex look for profile '\(raw)' — Original used"))
            }
            result.recipe.filterIntensity = 1
            result.namedSettings.insert(.filter)
            result.appliedCount += 1
            return true
        case "PostCropVignetteStyle":
            let styles: [String: PhotoVignetteStyle] = ["1": .highlightPriority, "2": .colorPriority, "3": .paintOverlay]
            guard let style = styles[raw] else { return nil }
            result.recipe.vignetteStyle = style
            result.namedSettings.insert(.vignetteStyle)
            result.appliedCount += 1
            return true
        default:
            return nil
        }
    }

    private static func applyStructured(_ target: LightroomMappingTable.StructuredTarget, raw: String, to result: inout LightroomMappingResult) {
        guard let value = number(raw) else { return }
        var color = result.recipe.color
        switch target {
        case let .grayMixer(band):
            color.grayMixer[band] = min(1, max(-1, value / 100))
            result.namedSettings.insert(.grayMixer(band))
        case let .calibration(path, key):
            color.calibration[keyPath: path] = min(1, max(-1, value / 100))
            result.namedSettings.insert(.calibration(key))
        case let .gradingHue(region):
            color.grading[region].hue = value.truncatingRemainder(dividingBy: 360)
            result.namedSettings.insert(.grading(region, "hue"))
        case let .gradingSaturation(region):
            color.grading[region].saturation = min(1, max(0, value / 100))
            result.namedSettings.insert(.grading(region, "saturation"))
        case let .gradingLuminance(region):
            color.grading[region].luminance = min(1, max(-1, value / 100))
            result.namedSettings.insert(.grading(region, "luminance"))
        case .gradingBlending:
            color.grading.blending = min(1, max(0, value / 100))
            result.namedSettings.insert(.gradingBlending)
        case .gradingBalance:
            color.grading.balance = min(1, max(-1, value / 100))
            result.namedSettings.insert(.gradingBalance)
        case let .region(path, key, isSplit):
            result.recipe.curve.region[keyPath: path] = isSplit ? min(0.95, max(0.05, value / 100)) : min(1, max(-1, value / 100))
            result.namedSettings.insert(.region(key))
        }
        result.recipe.color = color
        result.appliedCount += 1
    }

    /// "x, y" pairs on 0…255 onto the curve's 0…1 points.
    private static func applyCurve(_ channel: ToneCurveChannel, points: [String], to result: inout LightroomMappingResult) {
        let parsed: [CurvePoint] = points.compactMap { item in
            let parts = item.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return CurvePoint(x: min(1, max(0, x / 255)), y: min(1, max(0, y / 255)))
        }
        guard parsed.count >= 2 else { return }
        result.recipe.curve[channel] = parsed.sorted { $0.x < $1.x }
        result.namedSettings.insert(.curve(channel))
        result.appliedCount += 1
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
