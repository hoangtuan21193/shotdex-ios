import Foundation

/// A placeholder a text overlay can carry instead of a fixed string, so one saved
/// signature reads correctly on every photo it is stamped onto.
enum OverlayToken: String, CaseIterable, Identifiable, Sendable {
    case camera
    case lens
    case focal
    case aperture
    case shutter
    case iso
    case date
    case filename

    var id: String { rawValue }

    /// What the token expands to, written as the user will see it in the picker.
    var displayName: String {
        switch self {
        case .camera: "Camera"
        case .lens: "Lens"
        case .focal: "Focal length"
        case .aperture: "Aperture"
        case .shutter: "Shutter"
        case .iso: "ISO"
        case .date: "Date"
        case .filename: "Filename"
        }
    }

    var placeholder: String { "{\(rawValue)}" }
}

/// The resolved value of every token for one photo.
///
/// A nil field means the photo has no such value — an unindexed lens, a scan with
/// no exposure data — and the resolver removes the token *and* the prose that only
/// existed to introduce it, rather than leaving a gap.
struct OverlayTokenValues: Equatable, Sendable {
    var camera: String?
    var lens: String?
    var focal: String?
    var aperture: String?
    var shutter: String?
    var iso: String?
    var date: String?
    var filename: String?

    static let empty = OverlayTokenValues()

    init(
        camera: String? = nil,
        lens: String? = nil,
        focal: String? = nil,
        aperture: String? = nil,
        shutter: String? = nil,
        iso: String? = nil,
        date: String? = nil,
        filename: String? = nil
    ) {
        self.camera = camera
        self.lens = lens
        self.focal = focal
        self.aperture = aperture
        self.shutter = shutter
        self.iso = iso
        self.date = date
        self.filename = filename
    }

    /// Built from the indexed row rather than from a fresh EXIF read: the values
    /// here have already been through the camera and lens normalizers, so a text
    /// overlay says "Canon EOS R6" where the raw tag says "Canon EOS R6 Body".
    init(
        metadata: PhotoMetadata?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        guard let metadata else { return }
        camera = Self.trimmed(metadata.normalizedCameraModel ?? metadata.cameraModel)
        lens = Self.trimmed(metadata.normalizedLensModel ?? metadata.lensModel)
        focal = metadata.focalLength.flatMap(MetadataFormatter.focalLength)
        aperture = metadata.aperture.flatMap(MetadataFormatter.aperture)
        shutter = metadata.shutterSpeedDisplay
            ?? metadata.shutterSpeedSeconds.flatMap(MetadataFormatter.shutterSpeedCompact)
        iso = metadata.iso.flatMap(MetadataFormatter.iso)
        filename = Self.trimmed(metadata.originalFilename)
        if let value = metadata.creationDateValue {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            date = formatter.string(from: value)
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func value(for token: OverlayToken) -> String? {
        switch token {
        case .camera: camera
        case .lens: lens
        case .focal: focal
        case .aperture: aperture
        case .shutter: shutter
        case .iso: iso
        case .date: date
        case .filename: filename
        }
    }
}

/// Expands `{camera}`-style tokens in an overlay's text.
///
/// The awkward part is not substitution, it is what to do when a photo has no
/// value. A naive replace turns "Shot on {camera} · {lens} · {focal}" into
/// "Shot on Canon EOS R6 ·  · 85mm" on a photo with no lens tag. So the line is
/// first cut into separator-delimited segments, and a segment whose tokens all
/// came out empty is dropped whole — the separator and the prose that introduced
/// the token go with it.
enum OverlayTokenResolver {
    /// Characters that always start a separator between segments.
    private static let strongSeparators: Set<Character> = ["·", "•", "|", ","]
    /// Characters that separate only when they stand alone between spaces, so a
    /// literal "1/500" or "sun-drenched" in the template is left intact.
    private static let spacedSeparators: Set<Character> = ["-", "–", "—", "/"]

    static func resolve(_ template: String, values: OverlayTokenValues) -> String {
        // `omittingEmptySubsequences: false` keeps blank lines the user typed on
        // purpose; only a line whose whole content resolved away is dropped.
        let lines = template.split(separator: "\n", omittingEmptySubsequences: false)
        var resolved: [String] = []
        for line in lines {
            let string = String(line)
            guard containsKnownToken(string) else {
                resolved.append(string)
                continue
            }
            let value = resolveLine(string, values: values)
            if !value.isEmpty { resolved.append(value) }
        }
        return resolved.joined(separator: "\n")
    }

    /// Whether any resolvable token appears, so a line of plain prose is passed
    /// through untouched instead of going through the segment machinery.
    static func containsKnownToken(_ text: String) -> Bool {
        OverlayToken.allCases.contains { text.contains($0.placeholder) }
    }

    private static func resolveLine(_ line: String, values: OverlayTokenValues) -> String {
        var output = ""
        var pendingSeparator: String?
        for segment in segments(of: line) {
            guard let text = resolveSegment(segment.text, values: values) else { continue }
            if !output.isEmpty, let separator = pendingSeparator {
                output += separator
            }
            output += text
            pendingSeparator = segment.separator
        }
        return output
    }

    /// Nil when the segment should disappear: it had tokens, and every one of them
    /// was empty. A segment with no tokens is literal text the user typed and is
    /// always kept.
    private static func resolveSegment(_ segment: String, values: OverlayTokenValues) -> String? {
        var output = ""
        var index = segment.startIndex
        var tokenCount = 0
        var filledCount = 0

        while index < segment.endIndex {
            guard segment[index] == "{",
                  let close = segment[index...].firstIndex(of: "}")
            else {
                output.append(segment[index])
                index = segment.index(after: index)
                continue
            }
            let name = String(segment[segment.index(after: index)..<close])
            if let token = OverlayToken(rawValue: name) {
                tokenCount += 1
                if let value = values.value(for: token) {
                    filledCount += 1
                    output += value
                }
            } else {
                // Not one of ours: the user typed braces, so keep them.
                output += segment[index...close]
            }
            index = segment.index(after: close)
        }

        if tokenCount > 0, filledCount == 0 { return nil }
        let squashed = squashSpaces(output)
        return squashed.isEmpty && tokenCount > 0 ? nil : squashed
    }

    /// Removing a token mid-segment leaves a double space behind
    /// ("Shot on  handheld"), which reads as a typo in a burnt-in caption.
    private static func squashSpaces(_ text: String) -> String {
        var output = ""
        var lastWasSpace = false
        for character in text {
            let isSpace = character == " "
            if isSpace, lastWasSpace { continue }
            output.append(character)
            lastWasSpace = isSpace
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private struct Segment {
        var text: String
        /// The separator that followed this segment in the template, reused
        /// verbatim so "A | B" does not come back as "A · B". Nil at end of line.
        var separator: String?
    }

    private static func segments(of line: String) -> [Segment] {
        var result: [Segment] = []
        var current = ""
        var index = line.startIndex

        while index < line.endIndex {
            if let (separator, next) = separatorRun(in: line, at: index) {
                result.append(Segment(text: current, separator: separator))
                current = ""
                index = next
                continue
            }
            current.append(line[index])
            index = line.index(after: index)
        }
        result.append(Segment(text: current, separator: nil))
        return result
    }

    /// Matches a separator run starting at `index`, consuming the spaces on both
    /// sides so a dropped segment does not leave them behind.
    private static func separatorRun(
        in line: String,
        at index: String.Index
    ) -> (separator: String, next: String.Index)? {
        var cursor = index
        var leadingSpaces = ""
        while cursor < line.endIndex, line[cursor] == " " {
            leadingSpaces.append(" ")
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }

        let character = line[cursor]
        let isStrong = strongSeparators.contains(character)
        let isSpaced = spacedSeparators.contains(character)
        guard isStrong || isSpaced else { return nil }
        // A dash or slash is only a separator when it is spaced on both sides.
        if isSpaced, leadingSpaces.isEmpty { return nil }

        var afterSpaces = line.index(after: cursor)
        var trailingSpaces = ""
        while afterSpaces < line.endIndex, line[afterSpaces] == " " {
            trailingSpaces.append(" ")
            afterSpaces = line.index(after: afterSpaces)
        }
        if isSpaced, trailingSpaces.isEmpty { return nil }

        return (leadingSpaces + String(character) + trailingSpaces, afterSpaces)
    }
}
