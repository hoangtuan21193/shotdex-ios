import Foundation

/// SRT, WebVTT and ASS/SSA into `SubtitleDocument` (FS-23.03 §3). Keeps
/// italic, bold and line breaks; drops fonts, colors, effects and
/// coordinates; keeps an ASS line placed at the top at the top. Lenient:
/// a block it cannot read is skipped, never the whole file.
enum SubtitleParser {
    enum Format: String, Sendable {
        case srt
        case vtt
        case ass
    }

    /// From the text itself, with the file extension as the tie-breaker.
    static func detectFormat(_ text: String, fileExtension: String? = nil) -> Format {
        let head = text.prefix(4_096).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("WEBVTT") { return .vtt }
        if head.contains("[Script Info]") || head.contains("[Events]") || head.contains("Dialogue:") { return .ass }
        switch fileExtension?.lowercased() {
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        default: return .srt
        }
    }

    static func parse(_ text: String, format: Format) -> SubtitleDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        switch format {
        case .srt: return SubtitleDocument(cues: parseSRT(normalized))
        case .vtt: return SubtitleDocument(cues: parseVTT(normalized))
        case .ass: return SubtitleDocument(cues: parseASS(normalized))
        }
    }

    // MARK: SRT

    private static func parseSRT(_ text: String) -> [SubtitleCue] {
        blocks(text).compactMap { lines in
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = timing(lines[timingIndex]) else { return nil }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            return cue(start: start, end: end, markup: body)
        }
    }

    // MARK: WebVTT

    private static func parseVTT(_ text: String) -> [SubtitleCue] {
        blocks(text).compactMap { lines in
            guard let first = lines.first, !first.hasPrefix("WEBVTT"), !first.hasPrefix("NOTE"),
                  !first.hasPrefix("STYLE"), !first.hasPrefix("REGION"),
                  let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = timing(lines[timingIndex]) else { return nil }
            let settings = lines[timingIndex].components(separatedBy: "-->").last ?? ""
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            guard var cue = cue(start: start, end: end, markup: body) else { return nil }
            if let match = settings.firstMatch(of: #/line:(-?\d+(?:\.\d+)?)(%)?/#),
               let value = Double(match.1) {
                // `line:0` / `line:10%` sit at the top; negatives count from the bottom.
                let isTop = match.2 != nil ? value < 50 : value >= 0 && value < 5
                if isTop { cue.placement = .top }
            }
            return cue
        }
    }

    /// `00:01:05,000 --> 00:01:07,500` (SRT) or `01:05.000 --> 01:07.500 line:0` (VTT).
    private static func timing(_ line: String) -> (Int64, Int64)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = milliseconds(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = milliseconds(parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? "")
        else { return nil }
        return (start, max(start, end))
    }

    /// `h:mm:ss,mmm`, `hh:mm:ss.mmm`, `mm:ss.mmm`, ASS `h:mm:ss.cc`.
    static func milliseconds(_ stamp: String) -> Int64? {
        guard let match = stamp.wholeMatch(of: #/(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?/#),
              let minutes = Int64(match.2), let seconds = Int64(match.3) else { return nil }
        let hours = match.1.flatMap { Int64($0) } ?? 0
        var fraction: Int64 = 0
        if let digits = match.4 {
            let value = Int64(digits) ?? 0
            fraction = digits.count == 1 ? value * 100 : digits.count == 2 ? value * 10 : value
        }
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + fraction
    }

    private static func blocks(_ text: String) -> [[String]] {
        text.components(separatedBy: "\n\n").map { block in
            block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }.filter { !$0.isEmpty }
    }

    /// HTML-ish tags (`<i>`, `<b>`, `<font>`, `<c.x>`, `<v Name>`) plus the
    /// ASS overrides some SRT files carry (`{\an8}`, `{\i1}`).
    private static func cue(start: Int64, end: Int64, markup: String) -> SubtitleCue? {
        var lines: [[SubtitleRun]] = [[]]
        var italic = false
        var bold = false
        var placement = SubtitleCue.Placement.bottom
        var text = ""
        func flush() {
            if !text.isEmpty { lines[lines.count - 1].append(SubtitleRun(text: text, isItalic: italic, isBold: bold)) }
            text = ""
        }
        var index = markup.startIndex
        while index < markup.endIndex {
            let character = markup[index]
            if character == "<", let close = markup[index...].firstIndex(of: ">") {
                let tag = markup[markup.index(after: index)..<close].lowercased()
                flush()
                switch tag {
                case "i": italic = true
                case "/i": italic = false
                case "b": bold = true
                case "/b": bold = false
                default: break
                }
                index = markup.index(after: close)
                continue
            }
            if character == "{", let close = markup[index...].firstIndex(of: "}") {
                let block = String(markup[markup.index(after: index)..<close])
                flush()
                if block.hasPrefix("\\") {
                    let tags = overrides(block)
                    italic = tags.italic ?? italic
                    bold = tags.bold ?? bold
                    if tags.isTop { placement = .top }
                }
                index = markup.index(after: close)
                continue
            }
            if character == "\n" {
                flush()
                lines.append([])
            } else {
                text.append(character)
            }
            index = markup.index(after: index)
        }
        flush()
        lines = lines.map(trim).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return SubtitleCue(startMs: start, endMs: end, lines: lines, placement: placement)
    }

    private static func trim(_ line: [SubtitleRun]) -> [SubtitleRun] {
        var line = line.filter { !$0.text.isEmpty }
        if let first = line.first {
            line[0].text = String(first.text.drop(while: \.isWhitespace))
        }
        if let last = line.last {
            line[line.count - 1].text = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
        }
        let kept = line.filter { !$0.text.isEmpty }
        return kept.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } ? kept : []
    }

    // MARK: ASS / SSA

    private struct Overrides {
        var italic: Bool?
        var bold: Bool?
        var isTop = false
        /// `\p1`…: vector drawing — the text that follows is shapes.
        var drawing: Bool?
    }

    private static func overrides(_ block: String) -> Overrides {
        var result = Overrides()
        for tag in block.split(separator: "\\").map(String.init) {
            if let match = tag.wholeMatch(of: #/i(\d)/#) { result.italic = match.1 != "0" }
            else if let match = tag.wholeMatch(of: #/b(\d+)/#) { result.bold = match.1 != "0" }
            else if let match = tag.wholeMatch(of: #/an(\d)/#), let value = Int(match.1) { result.isTop = value >= 7 }
            // SSA `\a`: 5, 6, 7 (and 9–11 mid-top in some writers) are top.
            else if let match = tag.wholeMatch(of: #/a(\d{1,2})/#), let value = Int(match.1) { result.isTop = (5...7).contains(value) }
            else if let match = tag.wholeMatch(of: #/p(\d)/#) { result.drawing = match.1 != "0" }
        }
        return result
    }

    private struct Style {
        var italic = false
        var bold = false
        var isTop = false
    }

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var section = ""
        var styleFormat: [String] = []
        var eventFormat: [String] = []
        var styles: [String: Style] = [:]
        var cues: [SubtitleCue] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.lowercased()
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if section.contains("styles") {
                if key == "format" { styleFormat = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
                if key == "style" {
                    let fields = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    func field(_ name: String) -> String? { styleFormat.firstIndex(of: name).flatMap { $0 < fields.count ? fields[$0] : nil } }
                    let alignment = Int(field("alignment") ?? "") ?? 2
                    // V4+ uses numpad 7–9 for top; V4 (SSA) uses 5–7.
                    let isTop = section.contains("v4+") ? alignment >= 7 : (5...7).contains(alignment)
                    styles[field("name") ?? ""] = Style(
                        italic: (field("italic") ?? "0") != "0", bold: (field("bold") ?? "0") != "0", isTop: isTop
                    )
                }
            } else if section == "[events]" {
                if key == "format" { eventFormat = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
                guard key == "dialogue" else { continue }
                let format = eventFormat.isEmpty
                    ? ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
                    : eventFormat
                let fields = value.split(separator: ",", maxSplits: format.count - 1, omittingEmptySubsequences: false).map(String.init)
                func field(_ name: String) -> String? { format.firstIndex(of: name).flatMap { $0 < fields.count ? fields[$0] : nil } }
                guard let start = field("start").flatMap({ milliseconds($0.trimmingCharacters(in: .whitespaces)) }),
                      let end = field("end").flatMap({ milliseconds($0.trimmingCharacters(in: .whitespaces)) }),
                      let body = field("text") else { continue }
                let style = styles[field("style")?.trimmingCharacters(in: .whitespaces) ?? ""]
                    ?? styles[(field("style") ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")]
                    ?? Style()
                if let cue = assCue(start: start, end: max(start, end), body: body, style: style) { cues.append(cue) }
            }
        }
        return cues
    }

    private static func assCue(start: Int64, end: Int64, body: String, style: Style) -> SubtitleCue? {
        var lines: [[SubtitleRun]] = [[]]
        var italic = style.italic
        var bold = style.bold
        var placement: SubtitleCue.Placement = style.isTop ? .top : .bottom
        var drawing = false
        var text = ""
        func flush() {
            if !text.isEmpty, !drawing { lines[lines.count - 1].append(SubtitleRun(text: text, isItalic: italic, isBold: bold)) }
            text = ""
        }
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "{", let close = body[index...].firstIndex(of: "}") {
                flush()
                let tags = overrides(String(body[body.index(after: index)..<close]))
                italic = tags.italic ?? italic
                bold = tags.bold ?? bold
                drawing = tags.drawing ?? drawing
                if tags.isTop { placement = .top }
                index = body.index(after: close)
                continue
            }
            if character == "\\", body.index(after: index) < body.endIndex {
                let next = body[body.index(after: index)]
                if next == "N" || next == "n" {
                    flush()
                    lines.append([])
                    index = body.index(index, offsetBy: 2)
                    continue
                }
                if next == "h" {
                    text.append(" ")
                    index = body.index(index, offsetBy: 2)
                    continue
                }
            }
            text.append(character)
            index = body.index(after: index)
        }
        flush()
        lines = lines.map(trim).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return SubtitleCue(startMs: start, endMs: end, lines: lines, placement: placement)
    }
}
