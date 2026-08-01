import SwiftUI

/// One editable condition in the smart-album rule builder: a field picker, an
/// operator picker, a per-condition delete button, and a value editor whose
/// shape follows `field.kind`. The macOS Photos smart-album row, adapted to a
/// two-line iOS layout (field + operator + delete on top, value below).
struct SmartAlbumRuleRow: View {
    @Binding var rule: SmartAlbumRule
    let brands: [String]
    let bodies: [String]
    let lenses: [String]
    var places: [String] = []
    /// Removes this condition from the parent list.
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                fieldMenu
                if rule.field.kind != .favorite {
                    operatorMenu
                }
                Spacer(minLength: 0)
                deleteButton
            }
            valueEditor
        }
        .padding(.vertical, 4)
    }

    // MARK: Field & operator menus

    private var fieldMenu: some View {
        Menu {
            ForEach(RuleField.allCases) { field in
                Button(field.displayName) { selectField(field) }
            }
        } label: {
            menuToken(rule.field.displayName, emphasized: true)
        }
    }

    private var operatorMenu: some View {
        Menu {
            ForEach(rule.field.kind.allowedOperators) { op in
                Button(op.displayName) { rule.op = op }
            }
        } label: {
            menuToken(rule.op.displayName, emphasized: false)
        }
    }

    /// Trailing "−" button that removes this whole condition (replaces the old
    /// swipe-only delete and the value field's suggestion chevron).
    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Delete condition")
    }

    private func menuToken(_ text: String, emphasized: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .fontWeight(emphasized ? .semibold : .regular)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill), in: Capsule())
        .foregroundStyle(Color(.label))
    }

    /// Switching field resets the operator to that field's default and clears
    /// the now-meaningless operands.
    private func selectField(_ field: RuleField) {
        guard field != rule.field else { return }
        rule.field = field
        rule.op = field.defaultOperator
        rule.text = ""
        rule.number = nil
        rule.numberUpper = nil
        rule.boolValue = true
        rule.focalMode = .actual
        // "is on" is the default date operator; seed today so the DatePicker's
        // shown date is the committed value (rule valid, Save enabled) instead
        // of a displayed-but-nil date the user must tap to activate.
        if field.kind == .date, rule.op == .on {
            rule.number = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        }
    }

    // MARK: Value editor

    @ViewBuilder
    private var valueEditor: some View {
        switch rule.field.kind {
        case .text: textEditor
        case .choice: choiceEditor
        case .number: numberEditor
        case .date: dateEditor
        case .favorite: favoriteEditor
        }
    }

    /// Free-typed value with inline autocomplete: matching indexed values show
    /// as tappable tokens beneath the field (no dropdown button).
    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Value", text: $rule.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            if !matchingSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matchingSuggestions, id: \.self) { value in
                            Button { rule.text = value } label: {
                                Text(value)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.secondarySystemFill), in: Capsule())
                                    .foregroundStyle(Color(.label))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var choiceEditor: some View {
        Menu {
            ForEach(rule.field.choiceValues, id: \.value) { choice in
                Button(choice.label) { rule.text = choice.value }
            }
        } label: {
            HStack {
                Text(choiceLabel)
                    .foregroundStyle(rule.text.isEmpty ? .secondary : Color(.label))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var numberEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rule.field == .focalLength {
                Picker("Measure", selection: $rule.focalMode) {
                    Text("Actual").tag(FocalLengthMode.actual)
                    Text("FF Equivalent").tag(FocalLengthMode.equivalent)
                }
                .pickerStyle(.segmented)
            }
            if rule.op.needsUpperBound {
                HStack(spacing: 8) {
                    numberField("Min", text: boundText(\.number))
                    Text("to").foregroundStyle(.secondary)
                    numberField("Max", text: boundText(\.numberUpper))
                }
            } else {
                numberField(numberPrompt, text: boundText(\.number))
            }
        }
    }

    @ViewBuilder
    private var dateEditor: some View {
        switch rule.op {
        case .inLastDays:
            HStack(spacing: 8) {
                numberField("30", text: daysText)
                    .frame(maxWidth: 100)
                Text("days").foregroundStyle(.secondary)
                Spacer()
            }
        case .on, .before, .after:
            DatePicker("", selection: dateBinding(\.number), displayedComponents: .date)
                .labelsHidden()
        case .inRange:
            HStack(spacing: 8) {
                DatePicker("", selection: dateBinding(\.number), displayedComponents: .date)
                    .labelsHidden()
                Text("to").foregroundStyle(.secondary)
                DatePicker("", selection: dateBinding(\.numberUpper), displayedComponents: .date)
                    .labelsHidden()
            }
        default:
            EmptyView()
        }
    }

    private var favoriteEditor: some View {
        Picker("Favorite", selection: $rule.boolValue) {
            Text("Favorite").tag(true)
            Text("Not favorite").tag(false)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Editor helpers

    /// A rounded text field for a numeric operand. Focal length gets a trailing
    /// "mm" unit label so the user never types the unit into the value.
    private func numberField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .keyboardType(rule.field.numericKind == .shutter ? .default : .decimalPad)
            .textFieldStyle(.roundedBorder)
            .overlay(alignment: .trailing) {
                if rule.field == .focalLength {
                    Text("mm")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 10)
                        .allowsHitTesting(false)
                }
            }
    }

    private var numberPrompt: String {
        switch rule.field {
        case .aperture: "f-number"
        case .shutter: "e.g. 1/500"
        case .focalLength: "e.g. 50"
        default: "Value"
        }
    }

    /// String binding for a numeric operand. Focal length is restricted to
    /// digits and a decimal point so the "mm" suffix can't be typed into it;
    /// other fields parse/format per their numeric kind.
    private func boundText(_ key: WritableKeyPath<SmartAlbumRule, Double?>) -> Binding<String> {
        guard rule.field == .focalLength else { return numberText(key) }
        return Binding(
            get: { NumericFieldKind.double.format(rule[keyPath: key]) },
            set: { new in
                let digits = new.filter { $0.isNumber || $0 == "." }
                rule[keyPath: key] = NumericFieldKind.double.parse(digits)
            }
        )
    }

    /// String binding that parses/formats a numeric operand per the field kind.
    private func numberText(_ key: WritableKeyPath<SmartAlbumRule, Double?>) -> Binding<String> {
        Binding(
            get: { rule.field.numericKind.format(rule[keyPath: key]) },
            set: { rule[keyPath: key] = rule.field.numericKind.parse($0) }
        )
    }

    private var daysText: Binding<String> {
        Binding(
            get: { rule.number.map { String(Int($0.rounded())) } ?? "" },
            set: { rule.number = Double($0.filter(\.isNumber)) }
        )
    }

    private func dateBinding(_ key: WritableKeyPath<SmartAlbumRule, Double?>) -> Binding<Date> {
        Binding(
            get: {
                if let epoch = rule[keyPath: key] {
                    return Date(timeIntervalSince1970: epoch)
                }
                return Date()
            },
            set: { rule[keyPath: key] = $0.timeIntervalSince1970 }
        )
    }

    private var choiceLabel: String {
        rule.field.choiceValues.first { $0.value == rule.text }?.label ?? "Choose…"
    }

    /// Autocomplete source values for the current text field.
    private var suggestions: [String] {
        switch rule.field {
        case .cameraBrand: brands
        case .place: places
        case .cameraBody: bodies
        case .lens: lenses
        default: []
        }
    }

    /// Suggestions filtered by what the user has typed (case-insensitive
    /// substring), minus the value already entered, capped for layout.
    private var matchingSuggestions: [String] {
        let all = suggestions
        guard !all.isEmpty else { return [] }
        let query = rule.text.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [String] = []
        result.reserveCapacity(12)
        for value in all {
            guard query.isEmpty || value.lowercased().contains(query) else { continue }
            guard value.caseInsensitiveCompare(rule.text) != .orderedSame else { continue }
            result.append(value)
            if result.count == 12 { break }
        }
        return result
    }
}
