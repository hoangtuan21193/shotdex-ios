import SwiftUI

/// How a `NumericRangeField` parses and formats its text.
enum NumericFieldKind {
    case int      // ISO
    case double   // aperture, focal length
    case shutter  // seconds; accepts "1/500" or decimal
}

/// A `List` section with Min / Max text fields bound to a `NumericRangeFilter`
/// (either side may be left blank for an open-ended range). Optional `extra`
/// content renders as the first row of the section (used by focal length for
/// its Actual / FF-equivalent toggle).
struct NumericRangeField<Extra: View>: View {
    let title: String
    @Binding var range: NumericRangeFilter
    let kind: NumericFieldKind
    let footer: String?
    let extra: () -> Extra

    @State private var minText: String = ""
    @State private var maxText: String = ""

    init(
        title: String,
        range: Binding<NumericRangeFilter>,
        kind: NumericFieldKind = .double,
        footer: String? = nil,
        @ViewBuilder extra: @escaping () -> Extra
    ) {
        self.title = title
        _range = range
        self.kind = kind
        self.footer = footer
        self.extra = extra
    }

    var body: some View {
        Section {
            extra()
            HStack {
                TextField("Min", text: $minText)
                    .keyboardType(kind == .shutter ? .default : .decimalPad)
                    .onChange(of: minText) { _, new in
                        range.lowerBound = kind.parse(new)
                    }
                Divider()
                TextField("Max", text: $maxText)
                    .keyboardType(kind == .shutter ? .default : .decimalPad)
                    .onChange(of: maxText) { _, new in
                        range.upperBound = kind.parse(new)
                    }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
        .onAppear {
            minText = kind.format(range.lowerBound)
            maxText = kind.format(range.upperBound)
        }
    }
}

// MARK: Parsing / formatting

extension NumericFieldKind {
    /// Parses user text into a stored `Double?` (nil = empty / unparseable).
    /// `.shutter` also accepts a "1/500" fraction.
    func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch self {
        case .int, .double:
            return Double(trimmed)
        case .shutter:
            if trimmed.contains("/") {
                let parts = trimmed.split(separator: "/")
                guard parts.count == 2,
                      let num = Double(parts[0]),
                      let den = Double(parts[1]), den != 0
                else { return nil }
                return num / den
            }
            return Double(trimmed)
        }
    }

    /// Formats a stored value for display (empty string when nil).
    func format(_ value: Double?) -> String {
        guard let value else { return "" }
        switch self {
        case .int:
            return String(Int(value.rounded()))
        case .double:
            return Self.trimmed(value)
        case .shutter:
            if value > 0, value < 1 {
                return "1/\(Int((1 / value).rounded()))"
            }
            return Self.trimmed(value)
        }
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

extension NumericRangeField where Extra == EmptyView {
    init(
        title: String,
        range: Binding<NumericRangeFilter>,
        kind: NumericFieldKind = .double,
        footer: String? = nil
    ) {
        self.init(title: title, range: range, kind: kind, footer: footer) { EmptyView() }
    }
}
