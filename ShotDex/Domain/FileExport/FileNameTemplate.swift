import Foundation

/// What a file name is built from: one photo's own facts (FS-03.07b §5).
struct FileNameValues: Sendable, Equatable {
    /// The original file name without its extension: `DSCF1000`.
    var original: String
    /// When it was shot — or, with no capture date, when the asset was made.
    var captureDate: Date
    /// The model as the filter chip names it: `X-T5`. Nil or empty drops the token.
    var camera: String?
    var lens: String?
}

/// A file name template — `{date}_{camera}_{sequence}` — and how it becomes
/// a name (FS-03.07b §5). Export and card import share it (FS-20 AC-25).
/// Pure, so every rule is a unit test.
struct FileNameTemplate: Sendable, Equatable, Hashable {
    enum Token: String, CaseIterable, Sendable {
        case original, originalNumber, date, time, camera, lens, sequence

        var placeholder: String { "{\(rawValue)}" }
    }

    let pattern: String

    init(_ pattern: String) { self.pattern = pattern }

    static let originalName = FileNameTemplate("{original}")
    static let dateCameraSequence = FileNameTemplate("{date}_{camera}_{sequence}")
    static let dateOriginal = FileNameTemplate("{date}_{original}")
    /// The three the File Name screen lists above Custom, in order.
    static let builtIns: [FileNameTemplate] = [.originalName, .dateCameraSequence, .dateOriginal]

    /// Longest name before the extension; exFAT allows 255 UTF-16 units and
    /// Keep Both may still add ` (12)`.
    static let maximumLength = 200
    /// What exFAT and FAT refuse in a name, besides control characters.
    static let forbidden: Set<Character> = ["\"", "*", "/", ":", "<", ">", "?", "\\", "|"]
    /// What counts as a separator next to a token that has no value.
    static let separators: Set<Character> = ["_", "-", " ", ".", "·"]

    var isBuiltIn: Bool { Self.builtIns.contains(self) }

    /// A template with nothing in it can't name a file; Export dims.
    var isUsable: Bool { !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// `{sequence}` is three digits, four from a batch of 1,000, and so on.
    static func sequenceWidth(count: Int) -> Int { max(3, String(max(0, count)).count) }

    private enum Segment: Equatable {
        case literal(String)
        case token(Token)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var literal = ""
        var rest = Substring(pattern)
        while let open = rest.firstIndex(of: "{") {
            literal += rest[..<open]
            let after = rest[open...]
            if let close = after.firstIndex(of: "}"),
               let token = Token(rawValue: String(after[after.index(after: open)..<close])) {
                if !literal.isEmpty { result.append(.literal(literal)); literal = "" }
                result.append(.token(token))
                rest = after[after.index(after: close)...]
            } else {
                literal += "{"
                rest = after.dropFirst()
            }
        }
        literal += rest
        if !literal.isEmpty { result.append(.literal(literal)) }
        return result
    }

    /// The name before its extension, cleaned for any drive. A token with no
    /// value is left out with one separator beside it, so a screenshot's
    /// `{date}_{camera}_{sequence}` is `2026-09-21_003`, never `2026-09-21__003`.
    /// A template that leaves nothing names the file after its original.
    func baseName(
        for values: FileNameValues,
        sequence: Int,
        sequenceWidth: Int,
        timeZone: TimeZone = .current
    ) -> String {
        let segments = segments
        var texts: [String?] = segments.map { segment in
            switch segment {
            case .literal(let text): text
            case .token(let token): value(of: token, values, sequence: sequence, width: sequenceWidth, timeZone: timeZone)
            }
        }
        for (index, segment) in segments.enumerated() {
            guard case .token = segment, texts[index] == nil else { continue }
            if let before = Self.separatorLiteral(before: index, in: segments, texts: texts) {
                texts[before] = nil
            } else if let after = Self.separatorLiteral(after: index, in: segments, texts: texts) {
                texts[after] = nil
            }
        }
        var name = texts.compactMap { $0 }.joined()
        name = String(name.drop { Self.separators.contains($0) })
        while let last = name.last, Self.separators.contains(last) { name.removeLast() }
        let cleaned = Self.cleaned(name)
        return cleaned.isEmpty ? Self.cleaned(values.original) : cleaned
    }

    /// The literal right before `index`, if it is only separators and still
    /// there.
    private static func separatorLiteral(before index: Int, in segments: [Segment], texts: [String?]) -> Int? {
        guard index > 0, case .literal(let text) = segments[index - 1], texts[index - 1] != nil,
              text.allSatisfy({ separators.contains($0) }) else { return nil }
        return index - 1
    }

    private static func separatorLiteral(after index: Int, in segments: [Segment], texts: [String?]) -> Int? {
        guard index + 1 < segments.count, case .literal(let text) = segments[index + 1], texts[index + 1] != nil,
              text.allSatisfy({ separators.contains($0) }) else { return nil }
        return index + 1
    }

    private func value(of token: Token, _ values: FileNameValues, sequence: Int, width: Int, timeZone: TimeZone) -> String? {
        switch token {
        case .original: values.original
        case .originalNumber: Self.trailingDigits(of: values.original)
        case .date: Self.format(values.captureDate, "yyyy-MM-dd", timeZone)
        case .time: Self.format(values.captureDate, "HHmmss", timeZone)
        case .camera: values.camera.flatMap { $0.isEmpty ? nil : $0 }
        case .lens: values.lens.flatMap { $0.isEmpty ? nil : $0 }
        case .sequence: String(repeating: "0", count: max(0, width - String(sequence).count)) + String(sequence)
        }
    }

    /// `6123` from `IMG_6123`; nil when the name does not end in a digit.
    static func trailingDigits(of name: String) -> String? {
        let digits = name.reversed().prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits.reversed())
    }

    static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// One rule for every destination, because an SSD is usually exFAT:
    /// what FAT refuses becomes `-`, no leading `.`, at most 200 characters.
    static func cleaned(_ name: String) -> String {
        var result = String(name.map { character in
            if forbidden.contains(character) { return "-" }
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return "-" }
            return character
        })
        result = String(result.drop { $0 == "." })
        if result.count > maximumLength { result = String(result.prefix(maximumLength)) }
        return result
    }
}

/// One chip of the token grid. Export's File Name screen and Import's
/// inspector read the same eight from here (FS-20 AC-25), so the two can
/// never offer different words for one thing.
enum FileNameChip: Hashable, Sendable {
    case token(FileNameTemplate.Token)
    /// Plain words of the user's own, not a token: the chip adds `_Text`
    /// with the word marked for typing over.
    case text

    static let all: [FileNameChip] = [
        .token(.original), .token(.originalNumber), .token(.date), .token(.time),
        .token(.camera), .token(.lens), .token(.sequence), .text,
    ]

    static let textWord = "Text"

    /// `pattern` with this chip added at the end, and — for Text — where the
    /// word to type over sits in it.
    func appended(to pattern: String) -> (pattern: String, typedRange: Range<String.Index>?) {
        switch self {
        case .token(let token):
            return (pattern + token.placeholder, nil)
        case .text:
            let needsSeparator = !(pattern.isEmpty || pattern.last.map(FileNameTemplate.separators.contains) == true)
            let result = pattern + (needsSeparator ? "_" : "") + Self.textWord
            let start = result.index(result.endIndex, offsetBy: -Self.textWord.count)
            return (result, start..<result.endIndex)
        }
    }
}
