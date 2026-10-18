import SwiftUI

/// How a `NumericRangeField` parses and formats its text.
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
