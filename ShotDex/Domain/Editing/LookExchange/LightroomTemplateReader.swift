import Foundation

/// Reads a Lightroom `.lrtemplate` (FS-03.14a §1) — a Lua table — as data.
/// Only constants are accepted: strings, numbers, true / false / nil and
/// nested tables, 32 levels at most. Lua is never run: an expression, a
/// concatenation or a call refuses the whole preset. The one exception is
/// `ZSTR "…"`, Lightroom's localisation marker around a string literal, read
/// as the string it wraps.
enum LightroomTemplateReader {
    static let maximumDepth = 32

    enum Failure: Error, Equatable {
        /// Something that is not a constant: code, not data.
        case notData
        case noSettings

        var message: String {
            switch self {
            case .notData: "This preset holds code ShotDex won't run — only plain settings can be read"
            case .noSettings: "This preset has no develop settings"
            }
        }
    }

    indirect enum Value: Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case table([(key: String?, value: Value)])

        static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.string(a), .string(b)): a == b
            case let (.number(a), .number(b)): a == b
            case let (.bool(a), .bool(b)): a == b
            case (.null, .null): true
            case let (.table(a), .table(b)):
                a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
            default: false
            }
        }

        func field(_ name: String) -> Value? {
            guard case let .table(entries) = self else { return nil }
            return entries.first { $0.key == name }?.value
        }
    }

    static func read(_ data: Data) throws(Failure) -> LightroomSettings {
        let root = try parse(String(decoding: data, as: UTF8.self))
        guard let settingsTable = root.field("value")?.field("settings") ?? root.field("settings"),
              case let .table(entries) = settingsTable
        else { throw .noSettings }
        var settings = LightroomSettings()
        if case let .string(title) = root.field("title") { settings.name = displayName(title) }
        else if case let .string(name) = root.field("internalName") { settings.name = name }
        for (key, value) in entries {
            guard let key else { continue }
            switch value {
            case let .string(text): settings.values[key] = text
            case let .number(number): settings.values[key] = format(number)
            case let .bool(flag): settings.values[key] = flag ? "True" : "False"
            case .null: break
            case let .table(items):
                let numbers = items.compactMap { item -> Double? in
                    if case let .number(n) = item.value, item.key == nil { return n }
                    return nil
                }
                if !items.isEmpty, numbers.count == items.count, numbers.count.isMultiple(of: 2) {
                    // Curves: a flat list of x, y pairs.
                    settings.lists[key] = stride(from: 0, to: numbers.count, by: 2).map {
                        "\(format(numbers[$0])), \(format(numbers[$0 + 1]))"
                    }
                } else {
                    settings.structures.insert(key)
                }
            }
        }
        guard !settings.values.isEmpty || !settings.lists.isEmpty || !settings.structures.isEmpty else { throw .noSettings }
        return settings
    }

    /// "$$$/AgDevelop/Presets/Matte=Matte" → "Matte".
    private static func displayName(_ title: String) -> String {
        guard title.hasPrefix("$$$/"), let equals = title.firstIndex(of: "=") else { return title }
        return String(title[title.index(after: equals)...])
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
    }

    // MARK: Parsing

    private enum Token: Equatable {
        case name(String), string(String), number(Double), symbol(Character), end
    }

    private static func parse(_ text: String) throws(Failure) -> Value {
        var tokens = try tokenize(text)
        tokens.append(.end)
        var index = 0
        // `s = { … }` or `return { … }`.
        if case .name("return") = tokens[index] {
            index += 1
        } else if case .name = tokens[index], tokens.count > index + 1, tokens[index + 1] == .symbol("=") {
            index += 2
        }
        let value = try parseValue(tokens, &index, depth: 0)
        guard tokens[index] == .end else { throw .notData }
        return value
    }

    private static func parseValue(_ tokens: [Token], _ index: inout Int, depth: Int) throws(Failure) -> Value {
        guard depth <= maximumDepth else { throw .notData }
        let token = tokens[index]
        index += 1
        switch token {
        case let .string(text): return .string(text)
        case let .number(number): return .number(number)
        case .symbol("-"):
            guard case let .number(number) = tokens[index] else { throw .notData }
            index += 1
            return .number(-number)
        case .name("true"): return .bool(true)
        case .name("false"): return .bool(false)
        case .name("nil"): return .null
        case .name("ZSTR"):
            guard case let .string(text) = tokens[index] else { throw .notData }
            index += 1
            return .string(text)
        case .symbol("{"):
            var entries: [(key: String?, value: Value)] = []
            while tokens[index] != .symbol("}") {
                var key: String?
                if case let .name(name) = tokens[index], tokens[index + 1] == .symbol("=") {
                    key = name
                    index += 2
                } else if tokens[index] == .symbol("["), case let .string(name) = tokens[index + 1],
                          tokens[index + 2] == .symbol("]"), tokens[index + 3] == .symbol("=") {
                    key = name
                    index += 4
                }
                let value = try parseValue(tokens, &index, depth: depth + 1)
                entries.append((key, value))
                if tokens[index] == .symbol(",") || tokens[index] == .symbol(";") {
                    index += 1
                } else if tokens[index] != .symbol("}") {
                    throw .notData
                }
            }
            index += 1
            return .table(entries)
        default:
            // A bare name, a call, `..`, an operator: code, not data.
            throw .notData
        }
    }

    private static func tokenize(_ text: String) throws(Failure) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                // Comment to the end of the line (long comments too).
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "\"" || c == "'" {
                var value = ""
                i += 1
                while i < chars.count, chars[i] != c {
                    if chars[i] == "\\", i + 1 < chars.count {
                        i += 1
                        switch chars[i] {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        default: value.append(chars[i])
                        }
                    } else {
                        value.append(chars[i])
                    }
                    i += 1
                }
                guard i < chars.count else { throw .notData }
                i += 1
                tokens.append(.string(value))
                continue
            }
            if c == "[", i + 1 < chars.count, chars[i + 1] == "[" {
                var value = ""
                i += 2
                while i + 1 < chars.count, !(chars[i] == "]" && chars[i + 1] == "]") { value.append(chars[i]); i += 1 }
                guard i + 1 < chars.count else { throw .notData }
                i += 2
                tokens.append(.string(value))
                continue
            }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var literal = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "e" || chars[i] == "E"
                    || ((chars[i] == "-" || chars[i] == "+") && (literal.last == "e" || literal.last == "E")) {
                    literal.append(chars[i]); i += 1
                }
                guard let number = Double(literal) else { throw .notData }
                tokens.append(.number(number))
                continue
            }
            if c.isLetter || c == "_" {
                var name = ""
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { name.append(chars[i]); i += 1 }
                tokens.append(.name(name))
                continue
            }
            if "{}[]=,;-".contains(c) {
                tokens.append(.symbol(c))
                i += 1
                continue
            }
            // `(`, `.`, `+`, `..`, `#` and the rest belong to code.
            throw .notData
        }
        return tokens
    }
}
