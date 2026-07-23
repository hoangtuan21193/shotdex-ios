import SwiftUI

/// Read-only header shown atop a smart album's detail grid: the live match
/// count, the match mode when there is more than one rule, and each condition
/// rendered as a chip. The editable counterpart is `SmartAlbumRuleRow`.
struct SmartAlbumConditionsBar: View {
    let query: SmartAlbumQuery
    let matchCount: Int

    private var rules: [SmartAlbumRule] { query.validRules }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("^[\(matchCount) photo](inflect: true)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if rules.count > 1 {
                    Text("Match \(query.matchMode.word)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rules) { rule in
                        Text(rule.displaySummary)
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(Color(.label))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

extension SmartAlbumRule {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Human-readable one-line description used by the read-only chips.
    var displaySummary: String {
        if field.kind == .favorite {
            return boolValue ? "Favorite" : "Not favorite"
        }
        let value = displayValue
        guard !value.isEmpty else { return field.displayName }
        return "\(field.displayName) \(op.displayName) \(value)"
    }

    private var displayValue: String {
        switch field.kind {
        case .text:
            return text
        case .choice:
            if field == .fileType {
                return PhotoFileType(rawValue: text)?.displayName ?? text
            }
            return text // sensor-format rawValue is already its display name
        case .number:
            if op.needsUpperBound, let lower = number, let upper = numberUpper {
                return "\(formatNumber(lower))–\(formatNumber(upper))"
            }
            return number.map(formatNumber) ?? ""
        case .date:
            switch op {
            case .inLastDays:
                return "\(Int((number ?? 0).rounded())) days"
            case .on, .before, .after:
                return number.map { Self.dateFormatter.string(from: Date(timeIntervalSince1970: $0)) } ?? ""
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
