import Foundation

extension SearchIntentParser {
    /// A number as written, with whatever unit it carried.
    struct NumberLiteral: Equatable, Sendable {
        var value: Double
        /// Set when the literal was itself a range ("100-400").
        var upper: Double?
        /// The field the notation implies on its own, if any.
        var impliedField: RuleField?
    }

    /// Parses one token as a number. Notation carries meaning: `85mm` is a focal
    /// length, `1/500` a shutter speed, `f/1.8` an aperture — the same shorthands
    /// `SearchParser` has always understood, so a query that worked before still
    /// works.
    static func numberLiteral(_ token: String) -> NumberLiteral? {
        if let match = token.wholeMatch(of: /(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)/) {
            guard let lower = Double(match.1), let upper = Double(match.2) else { return nil }
            return NumberLiteral(value: min(lower, upper), upper: max(lower, upper))
        }
        if let match = token.wholeMatch(of: /f\/?(\d+(?:\.\d+)?)/) {
            return Double(match.1).map { NumberLiteral(value: $0, impliedField: .aperture) }
        }
        if let match = token.wholeMatch(of: /iso(\d+)/) {
            return Double(match.1).map { NumberLiteral(value: $0, impliedField: .iso) }
        }
        if let match = token.wholeMatch(of: /(\d+(?:\.\d+)?)mm/) {
            return Double(match.1).map { NumberLiteral(value: $0, impliedField: .focalLength) }
        }
        // A fraction is always a shutter speed; stored in seconds, as the column is.
        if let match = token.wholeMatch(of: /1\/(\d+(?:\.\d+)?)/) {
            guard let denominator = Double(match.1), denominator > 0 else { return nil }
            return NumberLiteral(value: 1 / denominator, impliedField: .shutter)
        }
        // "2s", "30s" — long exposures. Above a minute it is not a shutter speed.
        if let match = token.wholeMatch(of: /(\d+(?:\.\d+)?)s/) {
            guard let seconds = Double(match.1), seconds <= 60 else { return nil }
            return NumberLiteral(value: seconds, impliedField: .shutter)
        }
        if let value = Double(token) {
            return NumberLiteral(value: value)
        }
        return nil
    }

    /// Field keywords, as canonical tokens.
    static func numericField(_ token: String) -> RuleField? {
        switch token {
        case "f": .aperture
        case "iso": .iso
        case "shutter": .shutter
        case "focal", "mm": .focalLength
        default: nil
        }
    }

    static func comparison(_ token: String) -> RuleOperator? {
        switch token {
        // `>=` and `<=` have no column-level equivalent in `RuleOperator`, and
        // inventing one for a search phrase would widen the rule model for no
        // one else's benefit. "At least 1.4" reads as "greater than 1.4" closely
        // enough that the difference is a rounding error on real data.
        case ">", ">=": .greaterThan
        case "<", "<=": .lessThan
        default: nil
        }
    }

    /// Matches every numeric shape at `index`:
    /// `f > 1.2` · `> 200mm` · `iso 100-400` · `f 1.4 to 2.8` · `85mm` · `1/500`
    /// · `faster than 1/500`.
    static func numericRule(_ tokens: [Token], _ index: Int) -> (SmartAlbumRule, Int)? {
        var cursor = index
        var field: RuleField?
        var op: RuleOperator?

        // "faster/slower than" is about the exposure, not the number: a faster
        // shutter is a *smaller* number of seconds, which is the one comparison in
        // the app that inverts when spoken.
        if tokens[cursor].canonical == "faster" || tokens[cursor].canonical == "slower" {
            field = .shutter
            op = tokens[cursor].canonical == "faster" ? .lessThan : .greaterThan
            cursor += 1
        }

        if cursor < tokens.count, let named = numericField(tokens[cursor].canonical) {
            field = named
            cursor += 1
        }
        if cursor < tokens.count, let comparison = comparison(tokens[cursor].canonical) {
            // A comparison already read from "faster than" wins: "faster than"
            // followed by nothing else is complete on its own.
            op = op ?? comparison
            cursor += 1
        }
        // "from 24 to 70" — the range keyword comes first.
        var expectsRange = false
        if cursor < tokens.count, tokens[cursor].canonical == "from" {
            expectsRange = true
            cursor += 1
        }

        guard cursor < tokens.count, let literal = numberLiteral(tokens[cursor].canonical) else {
            return nil
        }
        cursor += 1
        var resolvedField = field ?? literal.impliedField
        var lower = literal.value
        var upper = literal.upper

        // A unit can trail its number: "> 200 mm", "iso 3200".
        if cursor < tokens.count, let trailing = numericField(tokens[cursor].canonical),
           tokens[cursor].canonical == "mm" {
            resolvedField = resolvedField ?? trailing
            cursor += 1
        }

        // "1.4 to 2.8" / "100 den 400".
        if upper == nil, cursor + 1 < tokens.count, tokens[cursor].canonical == "to",
           let second = numberLiteral(tokens[cursor + 1].canonical), second.upper == nil {
            upper = second.value
            resolvedField = resolvedField ?? second.impliedField
            cursor += 2
            if lower > upper! { swap(&lower, &upper!) }
        } else if expectsRange, upper == nil {
            // "from 24" with no "to" is not a range after all; keep it as a lower
            // bound rather than dropping what the user typed.
            op = op ?? .greaterThan
        }

        guard let resolvedField, resolvedField.kind == .number else { return nil }
        guard isPlausible(lower, for: resolvedField),
              upper.map({ isPlausible($0, for: resolvedField) }) ?? true
        else { return nil }

        let resolvedOperator: RuleOperator = if upper != nil {
            .inRange
        } else {
            op ?? .equalTo
        }
        let rule = SmartAlbumRule(
            field: resolvedField,
            op: resolvedOperator,
            number: lower,
            numberUpper: upper
        )
        return (rule, cursor - index)
    }

    /// Keeps a mis-parse from producing a rule that quietly matches nothing.
    /// Ranges are generous — the point is to reject "iso 1.4" and "f 3200", not to
    /// police unusual gear.
    static func isPlausible(_ value: Double, for field: RuleField) -> Bool {
        switch field {
        case .aperture: (0.5...128).contains(value)
        // Whole numbers only: "iso 1.4" is an aperture the user mislabelled, and
        // turning it into a rule would return an empty grid with a confident chip.
        case .iso: (6...4_000_000).contains(value) && value == value.rounded()
        case .shutter: (0.000_01...3_600).contains(value)
        case .focalLength: (1...5_000).contains(value)
        default: true
        }
    }
}
