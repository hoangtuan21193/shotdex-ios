import Foundation

/// How a condition reads in a token, a chip and VoiceOver — shared by the
/// smart album header and the search field.
extension SmartAlbumRule {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Human-readable one-line description used by the read-only tokens.
    var displaySummary: String {
        if field == .alsoOnServer {
            return serverSummary(text)
        }
        if field.kind == .favorite {
            return boolValue ? "Favorite" : "Not favorite"
        }
        let value = displayValue
        guard !value.isEmpty else { return field.displayName }
        return "\(field.displayName) \(op.displayName) \(value)"
    }

    /// `displaySummary` with a source shown by its name, and its folder:
    /// `Source is NAS Home › Shared` (FS-19.07 §7). The rule stores the
    /// source's id, so the caller hands over the names it has.
    func displaySummary(naming sourceNames: [String: String]) -> String {
        if field == .alsoOnServer, !text.isEmpty { return serverSummary(sourceLabel(sourceNames)) }
        guard field == .source, !text.isEmpty else { return displaySummary }
        return "\(field.displayName) \(op.displayName) \(sourceLabel(sourceNames))"
    }

    /// `compactDisplaySummary` with a source shown by its name and folder.
    func compactDisplaySummary(naming sourceNames: [String: String]) -> String {
        if field == .alsoOnServer, !text.isEmpty { return serverSummary(sourceLabel(sourceNames)) }
        guard field == .source, !text.isEmpty else { return compactDisplaySummary }
        let value = sourceLabel(sourceNames)
        return op == .isNot ? "\(compactFieldName) ≠ \(value)" : "\(compactFieldName) \(value)"
    }

    /// `Also on NAS Home › Shared` / `Not on NAS Home › Shared` — the chip
    /// names the server, not the field (FS-19.07 §7, user 2026-11-06).
    private func serverSummary(_ label: String) -> String {
        guard !label.isEmpty else { return field.displayName }
        return boolValue
            ? String(localized: "Also on \(label)", comment: "Smart album chip: photos that also have a copy on this server folder, e.g. Also on NAS Home › Shared")
            : String(localized: "Not on \(label)", comment: "Smart album chip: checked photos missing a copy on this server folder, e.g. Not on NAS Home › Shared")
    }

    /// `NAS Home › Shared/2025` — the id when the name is not known.
    private func sourceLabel(_ sourceNames: [String: String]) -> String {
        let name = sourceNames[text] ?? text
        let folder = (folder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return folder.isEmpty ? name : "\(name) › \(folder)"
    }

    /// Compact result-bar wording. The rule editor and VoiceOver can keep the
    /// full natural-language summary while chips use symbols that scan quickly:
    /// `ISO 100`, `f > 1.4`, `focal 50–85mm`.
    var compactDisplaySummary: String {
        switch field.kind {
        case .text:
            return compactTextSummary
        case .choice:
            let value = displayValue
            guard !value.isEmpty else { return compactFieldName }
            // "Original on This iPhone" — the Filter toggle's own words
            // (FS-06.10 §4); *is not* reads as the other answer.
            if field == .original, let state = OriginalPresence(rawValue: text) {
                let shown = op == .isNot ? (state == .onDevice ? OriginalPresence.iCloudOnly : .onDevice) : state
                return shown.chipTitle
            }
            // "Video" already names itself, the way a place name does — and
            // so does "Live Photo" or "edited".
            if field == .mediaType || field == .photoKind || field == .monthOfYear || field == .season || field == .dayOfWeek {
                return op == .isNot ? "≠ \(value)" : value
            }
            return op == .isNot
                ? "\(compactFieldName) ≠ \(value)"
                : "\(compactFieldName) \(value)"
        case .number:
            return compactNumberSummary
        case .date:
            return compactDateSummary
        case .favorite:
            return boolValue ? "Favorite" : "Not favorite"
        case .rating:
            return compactRatingSummary
        case .keyword, .caption:
            return KeywordCopy.chip(for: self)
        case .server:
            // Without the names an id would show; say the field instead.
            return boolValue
                ? String(localized: "Also on Server", comment: "Filter chip: an Also on Server condition whose server name is not at hand")
                : String(localized: "Not on Server", comment: "Filter chip: an Also on Server No condition whose server name is not at hand")
        }
    }

    /// `★ ≥ 4`, `★ ≤ 2`, `★ = 3` — the same glyph language as the quick
    /// filter's chip.
    private var compactRatingSummary: String {
        guard let number else { return MarkCopy.rating }
        let stars = Int(number.rounded())
        switch op {
        case .atLeast: return "★ ≥ \(stars)"
        case .atMost: return "★ ≤ \(stars)"
        default: return "★ = \(stars)"
        }
    }

    private var compactTextSummary: String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return compactFieldName }
        // A place name says what it is: "Fukuoka" reads better on a chip than
        // "place Fukuoka". A negated one still needs the marker.
        if field == .place, op == .contains || op == .isExactly {
            return value
        }
        // Leftover search words read as what was typed, quoted.
        if field == .anyText {
            return op == .doesNotContain ? "excludes \"\(value)\"" : "\"\(value)\""
        }
        switch op {
        case .contains:
            return "\(compactFieldName) \(value)"
        case .doesNotContain:
            return "\(compactFieldName) excludes \(value)"
        case .isExactly:
            return "\(compactFieldName) = \(value)"
        case .isNot:
            return "\(compactFieldName) ≠ \(value)"
        default:
            return "\(compactFieldName) \(value)"
        }
    }

    private var compactNumberSummary: String {
        guard let number else { return compactFieldName }
        let value = compactNumber(number)
        switch op {
        case .equalTo:
            if field == .aperture {
                return "f/\(value)"
            }
            return "\(compactFieldName) \(value)"
        case .greaterThan:
            return "\(compactFieldName) > \(value)"
        case .lessThan:
            return "\(compactFieldName) < \(value)"
        case .inRange:
            guard let numberUpper else { return "\(compactFieldName) \(value)" }
            return "\(compactFieldName) \(value)–\(compactNumber(numberUpper))"
        default:
            return "\(compactFieldName) \(value)"
        }
    }

    private var compactDateSummary: String {
        switch op {
        case .on, .inMonth:
            return "date \(displayValue)"
        case .inLastDays:
            return "last \(Int((number ?? 0).rounded()))\((unit ?? .days).letter)"
        case .notInLast:
            return "older than \(Int((number ?? 0).rounded()))\((unit ?? .days).letter)"
        case .before:
            return "date < \(displayValue)"
        case .after:
            return "date > \(displayValue)"
        case .inRange:
            return "date \(displayValue)"
        default:
            return "date \(displayValue)"
        }
    }

    private var compactFieldName: String {
        switch field {
        case .cameraBrand: "brand"
        case .cameraBody: "camera"
        case .lens: "lens"
        case .sensorFormat: "sensor"
        case .fileType, .filename: "file"
        case .mediaType: "media"
        case .place: "place"
        case .iso: "ISO"
        case .aperture: "f"
        case .shutter: "shutter"
        case .focalLength: focalMode == .equivalent ? "focal eq" : "focal"
        case .dateTaken: "date"
        case .favorite: "favorite"
        case .rating: "★"
        case .flag: MarkCopy.flag.lowercased()
        case .keyword: "keyword"
        case .caption: "caption"
        case .anyText: "text"
        case .source: "source"
        case .original: "original"
        case .alsoOnServer: "server"
        case .photoKind: "photo"
        case .monthOfYear: "month"
        case .season: "season"
        case .dayOfWeek: "day"
        }
    }

    private func compactNumber(_ value: Double) -> String {
        switch field {
        case .iso:
            return NumericFieldKind.int.format(value)
        case .aperture:
            return NumericFieldKind.double.format(value)
        case .shutter:
            return "\(NumericFieldKind.shutter.format(value))s"
        case .focalLength:
            return "\(NumericFieldKind.double.format(value))mm"
        default:
            return field.numericKind.format(value)
        }
    }

    private var displayValue: String {
        switch field.kind {
        case .text:
            return text
        case .choice:
            if field == .fileType {
                return PhotoFileType(rawValue: text)?.displayName ?? text
            }
            if field == .mediaType {
                return MediaKind(rawValue: text)?.displayName ?? text
            }
            if field == .flag {
                return SmartAlbumFlagValue(rawValue: text)?.label ?? text
            }
            if field == .original {
                return OriginalPresence(rawValue: text)?.label ?? text
            }
            if field == .photoKind {
                return PhotoKind(rawValue: text)?.label ?? text
            }
            if field == .monthOfYear {
                return CaptureMonthOfYear(value: text)?.label ?? text
            }
            if field == .season {
                return CaptureSeason(rawValue: text)?.label ?? text
            }
            if field == .dayOfWeek {
                return CaptureWeekday(rawValue: text)?.label ?? text
            }
            return text // sensor-format rawValue is already its display name
        case .number:
            if op.needsUpperBound, let lower = number, let upper = numberUpper {
                return "\(formatNumber(lower))–\(formatNumber(upper))"
            }
            return number.map(formatNumber) ?? ""
        case .date:
            switch op {
            case .inLastDays, .notInLast:
                return "\(Int((number ?? 0).rounded())) \((unit ?? .days).label)"
            case .on, .before, .after:
                return number.map { Self.dateFormatter.string(from: Date(timeIntervalSince1970: $0)) } ?? ""
            case .inMonth:
                return number.map { CaptureMonth(containing: Date(timeIntervalSince1970: $0)).abbreviatedName() } ?? ""
            case .inRange:
                guard let lower = number, let upper = numberUpper else { return "" }
                let lo = Self.dateFormatter.string(from: Date(timeIntervalSince1970: lower))
                let hi = Self.dateFormatter.string(from: Date(timeIntervalSince1970: upper))
                return "\(lo)–\(hi)"
            default:
                return ""
            }
        case .favorite:
            return ""
        case .rating:
            return number.map { MarkCopy.starsAccessibility(Int($0.rounded())) } ?? ""
        case .keyword:
            return op.needsValue ? text : ""
        case .caption, .server:
            return text
        }
    }

    private func formatNumber(_ value: Double) -> String {
        switch field {
        case .aperture:
            return "f/\(NumericFieldKind.double.format(value))"
        case .focalLength:
            return "\(NumericFieldKind.double.format(value))mm\(focalMode == .equivalent ? "e" : "")"
        case .shutter:
            return "\(NumericFieldKind.shutter.format(value))s"
        default:
            return field.numericKind.format(value)
        }
    }
}

extension SmartAlbumRuleGroup {
    /// `(Lens is FE 85mm F1.8 or Lens is XF56mm)` — a group as one chip:
    /// its conditions joined by its own and/or (FS-06.08 §2b).
    func displaySummary(naming sourceNames: [String: String] = [:], compact: Bool = false) -> String {
        let parts = validRules.map { compact ? $0.compactDisplaySummary(naming: sourceNames) : $0.displaySummary(naming: sourceNames) }
        let joined = matchMode == .any ? parts.formatted(.list(type: .or)) : parts.formatted(.list(type: .and))
        return "(\(joined))"
    }
}

extension SmartAlbumQuery {
    /// The query less one condition — a rule or a whole nested group — as a
    /// chip's × removes it.
    func removingCondition(_ id: UUID) -> SmartAlbumQuery {
        var updated = self
        updated.rules.removeAll { $0.id == id }
        updated.groups.removeAll { $0.id == id }
        return updated
    }
}
