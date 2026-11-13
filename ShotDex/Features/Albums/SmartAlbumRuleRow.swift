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
    /// Photos keywords, most photos first (iOS 27) — the Keyword field's
    /// suggestions (FS-02.07 §7).
    var keywords: [String] = []
    /// The Source field's choices, (id, name) — read by the builder, since
    /// sources change and the other choice sets do not.
    var sources: [(value: String, label: String)] = []
    /// Server sources, (id, name) — the Also on Server field's choices
    /// (FS-19.07 §7). Empty keeps the field and says how to add one (AC-247).
    var servers: [(value: String, label: String)] = []
    /// Sources whose folder can be browsed for a narrower condition (FS-19.07 §7).
    var folderSources: Set<String> = []
    /// Opens the folder browser for the rule's source.
    var onChooseFolder: (() -> Void)?
    /// Inserts a blank condition right below this one (Photos' **+**,
    /// FS-06.08 §3c). Nil hides the button.
    var onAddBelow: (() -> Void)? = nil
    /// Removes this condition from the parent list.
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                fieldMenu
                if !rule.field.kind.allowedOperators.isEmpty {
                    operatorMenu
                }
                Spacer(minLength: 0)
                rowButtons
            }
            valueEditor
        }
        .padding(.vertical, 4)
    }

    // MARK: Field & operator menus

    private var fieldMenu: some View {
        Menu {
            ForEach(fieldChoices) { field in
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

    /// Trailing − and +, as on a Photos condition row (FS-06.08 §3c D2): −
    /// removes this condition, + inserts a blank one right below it. Each
    /// glyph sits in a 44pt target; the targets touch, the glyphs are 16pt
    /// apart.
    private var rowButtons: some View {
        HStack(spacing: 0) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Remove Condition", comment: "Smart album condition row: the − button"))
            if let onAddBelow {
                Button(action: onAddBelow) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Add Condition Below", comment: "Smart album condition row: the + button, inserts a condition under this one"))
            }
        }
        .padding(.trailing, -10)
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
        .foregroundStyle(Color.primary)
    }

    /// Switching field keeps what still fits — the operator, a number range
    /// between number fields, text between text fields (FS-06.08 §3c A4) —
    /// and clears the rest.
    private func selectField(_ field: RuleField) {
        guard field != rule.field else { return }
        let kept = rule.changingField(to: field)
        rule = kept
        guard kept.number == nil, kept.text.isEmpty else { return }
        // "is on" is the default date operator; seed today so the DatePicker's
        // shown date is the committed value (rule valid, Save enabled) instead
        // of a displayed-but-nil date the user must tap to activate.
        // A rating condition is complete from the start, like a date one.
        if field.kind == .rating { rule.number = 4 }
        // The value a Photo condition is most often about.
        if field == .photoKind { rule.text = PhotoKind.favorite.rawValue }
        // One server: it is the only answer, so the count shows at once (AC-248).
        if field == .alsoOnServer, servers.count == 1 { rule.text = servers[0].value }
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
        case .rating: ratingEditor
        // `has any keyword` / `has no keywords` test nothing typed: no field.
        case .keyword: if rule.op.needsValue { textEditor }
        case .caption: textEditor
        case .server: serverEditor
        }
    }

    /// Also on Server: Yes / No, the server, its folder (FS-19.07 §7).
    @ViewBuilder
    private var serverEditor: some View {
        if servers.isEmpty, rule.text.isEmpty {
            // No server on this device: say where one comes from rather than
            // offer an empty menu (AC-247). The condition stays incomplete.
            Text(Self.noServerHint)
                .font(.footnote)
                .foregroundStyle(Self.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            serverChoices
        }
    }

    static let noServerHint = String(
        localized: "No server is a source on this device yet. In Settings › File Servers, open the server and turn on Add as Source — a connected server alone is not read.",
        comment: "Smart album Also on Server condition when no server source has been added")

    @ViewBuilder
    private var serverChoices: some View {
        Picker(RuleField.alsoOnServer.displayName, selection: $rule.boolValue) {
            Text(String(localized: "Yes", comment: "Smart album Also on Server condition: the photo has a copy there")).tag(true)
            Text(String(localized: "No", comment: "Smart album Also on Server condition: the photo is checked and missing a copy there")).tag(false)
        }
        .pickerStyle(.segmented)
        choiceMenu
        if !rule.text.isEmpty, folderSources.contains(rule.text), let onChooseFolder {
            folderButton(onChooseFolder)
        }
    }

    /// Every selectable field — Also on Server too when there is no server,
    /// so the condition can be found before its server is added (AC-247).
    private var fieldChoices: [RuleField] { RuleField.selectableCases }

    /// 0–5 as one segmented row: five stars and zero fit a 402pt phone.
    private var ratingEditor: some View {
        Picker(MarkCopy.rating, selection: Binding(
            get: { Int((rule.number ?? 0).rounded()) },
            set: { rule.number = Double($0) }
        )) {
            ForEach(StarRating.range, id: \.self) { stars in
                Text(stars == 0 ? "0" : "\(stars)★")
                    .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                    .tag(stars)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Free-typed value with inline autocomplete: matching indexed values show
    /// as tappable tokens beneath the field (no dropdown button).
    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Value", text: $rule.text)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .textFieldStyle(.roundedBorder)
            if !matchingSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingSuggestions, id: \.self) { value in
                            Button { rule.text = value } label: {
                                Text(value)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.secondarySystemFill), in: Capsule())
                                    .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var choiceEditor: some View {
        choiceMenu
        if rule.field == .source, folderSources.contains(rule.text), let onChooseFolder {
            folderButton(onChooseFolder)
        }
    }

    /// `Folder  Shared ›` — empty is the whole source (FS-19.07 §7).
    private func folderButton(_ action: @escaping () -> Void) -> some View {
        let folder = (rule.folder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let value = folder.isEmpty
            ? String(localized: "All Folders", comment: "Smart album Source condition: no folder chosen, the whole source")
            : folder
        return Button(action: action) {
            HStack(spacing: 6) {
                Text(String(localized: "Folder", comment: "Smart album Source condition: the folder row"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Folder, \(value)", comment: "VoiceOver: the smart album folder row and its value"))
    }

    private var choiceMenu: some View {
        Menu {
            ForEach(choices, id: \.value) { choice in
                Button(choice.label) {
                    if rule.text != choice.value { rule.folder = nil }
                    rule.text = choice.value
                }
            }
        } label: {
            HStack {
                // `Server        NAS Home ⌃⌄` like the Folder row under it; the
                // menu label would tint a `.secondary` style, so the colour is
                // named outright (board PH_SmartAlbumEditor).
                if rule.field == .alsoOnServer {
                    Text(String(localized: "Server", comment: "Smart album Also on Server condition: the server row"))
                        .foregroundStyle(Self.secondaryText)
                    Spacer()
                }
                Text(choiceLabel)
                    .foregroundStyle(rule.text.isEmpty ? Self.secondaryText : Color.primary)
                if rule.field != .alsoOnServer { Spacer() }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        case .inLastDays, .notInLast:
            // N and a unit, as Photos' "is in the last [2] [weeks]" (FS-06.08 §3c).
            HStack(spacing: 8) {
                numberField("30", text: daysText)
                    .frame(maxWidth: 100)
                Picker(String(localized: "Unit", comment: "Smart album date condition: the days/weeks/months/years menu"),
                       selection: Binding(get: { rule.unit ?? .days }, set: { rule.unit = $0 == .days ? nil : $0 })) {
                    ForEach(DateUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
            }
        case .on, .before, .after:
            DatePicker("", selection: dateBinding(\.number), displayedComponents: .date)
                .labelsHidden()
        case .inMonth:
            monthEditor
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

    /// Month and year, each a menu — a day picker would ask for a day the
    /// condition then ignores.
    private var monthEditor: some View {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        return HStack(spacing: 8) {
            Picker("Month", selection: monthBinding(\.month)) {
                ForEach(1...12, id: \.self) { month in
                    Text(calendar.standaloneMonthSymbols[month - 1]).tag(month)
                }
            }
            Picker("Year", selection: monthBinding(\.year)) {
                ForEach((currentYear - 60...currentYear).reversed(), id: \.self) { year in
                    Text(verbatim: String(year)).tag(year)
                }
            }
            Spacer()
        }
        .pickerStyle(.menu)
    }

    /// One part of the rule's month, stored back as that month's anchor.
    private func monthBinding(_ part: WritableKeyPath<CaptureMonth, Int>) -> Binding<Int> {
        Binding(
            get: { selectedMonth[keyPath: part] },
            set: { value in
                var month = selectedMonth
                month[keyPath: part] = value
                rule.number = month.anchorDate().timeIntervalSince1970
            }
        )
    }

    /// The rule's month, or this month while none is stored yet.
    private var selectedMonth: CaptureMonth {
        CaptureMonth(containing: rule.number.map { Date(timeIntervalSince1970: $0) } ?? .now)
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
#if os(iOS)
            .keyboardType(rule.field.numericKind == .shutter ? .default : .decimalPad)
#endif
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

    /// Grey that a Menu label does not tint (UIKit and AppKit name it apart).
    private static var secondaryText: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color(nsColor: .secondaryLabelColor)
        #endif
    }

    private var choiceLabel: String {
        if let label = choices.first(where: { $0.value == rule.text })?.label { return label }
        guard rule.field == .alsoOnServer else { return "Choose…" }
        // A server since removed: the condition matches nothing (AC-254).
        return rule.text.isEmpty
            ? String(localized: "Choose Server", comment: "Smart album Also on Server condition: no server picked yet")
            : String(localized: "Server Removed", comment: "Smart album Also on Server condition: its server is no longer a source")
    }

    private var choices: [(value: String, label: String)] {
        switch rule.field {
        case .source: sources
        case .alsoOnServer: servers
        default: rule.field.choiceValues
        }
    }

    /// Autocomplete source values for the current text field.
    private var suggestions: [String] {
        switch rule.field {
        case .cameraBrand: brands
        case .place: places
        case .cameraBody: bodies
        case .lens: lenses
        case .keyword: keywords
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
