import SwiftUI

/// One condition of the Mac smart album editor on one line (board
/// `MAC_SmartAlbumEditor`): field popup 136, comparison popup 128, the value,
/// then − and +. A Source or Also on Server condition on a browsable source
/// adds the Folder line under it.
struct MacRuleLine: View {
    @Binding var rule: SmartAlbumRule
    let options: MacRuleOptions
    /// Inside a group: indented, and + adds only a condition.
    var isNested = false
    /// ⌥ is down: + adds a group (Finder's predicate editor).
    var addsGroup = false
    var onChooseFolder: () -> Void
    var onRemove: () -> Void
    var onAdd: () -> Void
    var onAddGroup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                fieldPopup
                comparison
                value
                Spacer(minLength: 0)
                MacRuleLineButton(systemImage: "minus", label: String(localized: "Remove Condition", comment: "Mac smart album editor: remove one condition"),
                                  action: onRemove)
                addButton
            }
            .frame(height: MacRuleLine.height)
            .padding(.leading, isNested ? 28 : 8)
            .padding(.trailing, 8)
            if showsFolder {
                folderLine
            }
        }
    }

    /// 31 + the 1pt divider under each line: the board's 32 pitch.
    static let height: CGFloat = 31

    // MARK: Field and comparison

    private var fieldPopup: some View {
        Picker(String(localized: "Condition field", comment: "VoiceOver: the smart album condition's field popup"),
               selection: Binding(get: { rule.field }, set: { select($0) })) {
            ForEach(options.fields) { field in
                Text(field.displayName).tag(field)
            }
        }
        .labelsHidden()
        .frame(width: isNested ? 116 : 136)
    }

    @ViewBuilder
    private var comparison: some View {
        switch rule.field.kind {
        case .server:
            // Yes / No sits where the comparison would (board).
            Picker(RuleField.alsoOnServer.displayName, selection: $rule.boolValue) {
                Text("Yes", comment: "Smart album Also on Server condition: the photo has a copy there").tag(true)
                Text("No", comment: "Smart album Also on Server condition: the photo is checked and missing a copy there").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(MacTheme.accent)
            .frame(width: 128)
        case .favorite:
            Picker(RuleField.favorite.displayName, selection: $rule.boolValue) {
                Text("is", comment: "Mac smart album Favorite condition: the photo is a favorite").tag(true)
                Text("is not", comment: "Mac smart album Favorite condition: the photo is not a favorite").tag(false)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(width: 128)
        default:
            Picker(String(localized: "Comparison", comment: "VoiceOver: the smart album condition's comparison popup"), selection: $rule.op) {
                ForEach(rule.field.kind.allowedOperators) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .labelsHidden()
            // A popup sizes to its longest item: fill the column so every line's value starts at one x.
            .frame(maxWidth: .infinity)
            .frame(width: 128)
            .onChange(of: rule.op) { _, op in seedDate(for: op) }
        }
    }

    /// A field change keeps what still fits — the comparison when the new
    /// field has it, numbers between number fields, text between text fields
    /// (FS-06.08 §3c A4) — and seeds the rest.
    private func select(_ field: RuleField) {
        guard field != rule.field else { return }
        var next = rule.changingField(to: field)
        Self.seed(&next, options: options)
        rule = next
    }

    private func seedDate(for op: RuleOperator) {
        Self.seedDate(&rule)
    }

    /// What a fresh line on its field starts with: a rating of 4, the one
    /// server when there is one, a complete date. Used by a field change and
    /// by + (a new line on the same field).
    static func seed(_ rule: inout SmartAlbumRule, options: MacRuleOptions) {
        if rule.field.kind == .rating, rule.number == nil { rule.number = 4 }
        if rule.field == .alsoOnServer, rule.text.isEmpty, options.servers.count == 1 { rule.text = options.servers[0].value }
        seedDate(&rule)
    }

    /// A date comparison starts complete: the date shown is the one kept.
    static func seedDate(_ rule: inout SmartAlbumRule) {
        guard rule.field.kind == .date else { return }
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        switch rule.op {
        case .on, .before, .after, .inMonth: if rule.number == nil { rule.number = today }
        case .inRange:
            if rule.number == nil { rule.number = today }
            if rule.numberUpper == nil { rule.numberUpper = today }
        case .inLastDays, .notInLast: if (rule.number ?? 0) <= 0 { rule.number = 30 }
        default: break
        }
    }

    // MARK: Value

    @ViewBuilder
    private var value: some View {
        switch rule.field.kind {
        case .text, .caption: textField(width: rule.field == .lens || rule.field == .cameraBody ? 200 : 170)
        case .keyword: if rule.op.needsValue { textField(width: 170) }
        case .choice: choicePopup
        case .server:
            if options.servers.isEmpty, rule.text.isEmpty {
                // No server on this Mac: where one comes from, not an empty popup (AC-247).
                Text("Add a server in Settings › Sources", comment: "Mac smart album Also on Server condition when no server source has been added")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(String(localized: "No server on this Mac yet. Add one in Settings › Sources, then this condition can ask which photos also have a copy there.", comment: "Mac smart album Also on Server condition: tooltip when no server source has been added"))
            } else {
                choicePopup
            }
        case .number: numberValue
        case .date: dateValue
        case .rating: MacRuleStars(rating: Binding(get: { Int((rule.number ?? 0).rounded()) }, set: { rule.number = Double($0) }))
        case .favorite: EmptyView()
        }
    }

    private func textField(width: CGFloat) -> some View {
        let label = String(localized: "\(rule.field.displayName) value", comment: "Mac smart album editor: a condition's typed value")
        return TextField(label, text: $rule.text)
            .labelsHidden()
            // A hidden label leaves VoiceOver only the value to read.
            .accessibilityLabel(label)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputSuggestions {
                ForEach(options.suggestions(for: rule.field, typed: rule.text), id: \.self) { value in
                    Text(value).textInputCompletion(value)
                }
            }
            .frame(width: width)
    }

    private var choicePopup: some View {
        let choices = options.choices(for: rule.field)
        return Picker(rule.field == .alsoOnServer ? String(localized: "Server", comment: "Smart album Also on Server condition: the server row")
                                                  : String(localized: "\(rule.field.displayName) value", comment: "Mac smart album editor: a condition's typed value"),
                      selection: Binding(get: { rule.text }, set: { new in
                          if new != rule.text { rule.folder = nil }
                          rule.text = new
                      })) {
            if !choices.contains(where: { $0.value == rule.text }) {
                Text(choicePlaceholder).tag(rule.text)
            }
            ForEach(choices, id: \.value) { choice in
                Text(choice.label).tag(choice.value)
            }
        }
        .labelsHidden()
        .frame(width: 170)
    }

    private var choicePlaceholder: String {
        guard rule.field == .alsoOnServer else { return String(localized: "Choose…", comment: "Mac smart album editor: no value picked yet") }
        // A server since removed: the condition matches nothing (AC-254).
        return rule.text.isEmpty
            ? String(localized: "Choose Server", comment: "Smart album Also on Server condition: no server picked yet")
            : String(localized: "Server Removed", comment: "Smart album Also on Server condition: its server is no longer a source")
    }

    @ViewBuilder
    private var numberValue: some View {
        if rule.op.needsUpperBound {
            numberField(\.number, prompt: String(localized: "From", comment: "Mac smart album editor: a range's lower value"))
            Text("to", comment: "Mac smart album editor: between a range's two values").foregroundStyle(.secondary)
            numberField(\.numberUpper, prompt: String(localized: "To", comment: "Mac smart album editor: a range's upper value"))
        } else {
            numberField(\.number, prompt: rule.field.displayName)
        }
        if let unit {
            Text(unit).foregroundStyle(.secondary)
        }
        if rule.field == .focalLength {
            Picker(String(localized: "Measure", comment: "Mac smart album editor: actual or full-frame equivalent focal length"),
                   selection: $rule.focalMode) {
                Text("Actual", comment: "Smart album focal length: as the lens reads").tag(FocalLengthMode.actual)
                Text("FF Equiv.", comment: "Smart album focal length: full-frame equivalent").tag(FocalLengthMode.equivalent)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var unit: String? {
        switch rule.field {
        case .shutter: String(localized: "s", comment: "Mac smart album editor: seconds, after a shutter speed")
        case .focalLength: String(localized: "mm", comment: "Mac smart album editor: millimetres, after a focal length")
        default: nil
        }
    }

    private func numberField(_ key: WritableKeyPath<SmartAlbumRule, Double?>, prompt: String) -> some View {
        TextField(prompt, text: Binding(
            get: { rule.field.numericKind.format(rule[keyPath: key]) },
            set: { rule[keyPath: key] = rule.field.numericKind.parse($0) }
        ))
        .labelsHidden()
        .accessibilityLabel(prompt)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 76)
    }

    @ViewBuilder
    private var dateValue: some View {
        switch rule.op {
        case .on, .before, .after:
            datePicker(\.number, label: String(localized: "Date", comment: "Mac smart album editor: a date condition's date"))
        case .inRange:
            datePicker(\.number, label: String(localized: "From", comment: "Mac smart album editor: a range's lower value"))
            Text("to", comment: "Mac smart album editor: between a range's two values").foregroundStyle(.secondary)
            datePicker(\.numberUpper, label: String(localized: "To", comment: "Mac smart album editor: a range's upper value"))
        case .inMonth:
            monthValue
        case .inLastDays, .notInLast:
            TextField(String(localized: "Amount", comment: "Mac smart album editor: how many days back"), text: Binding(
                get: { rule.number.map { String(Int($0.rounded())) } ?? "" },
                set: { rule.number = Double($0.filter(\.isNumber)) }
            ))
            .labelsHidden()
            .accessibilityLabel(String(localized: "Amount", comment: "Mac smart album editor: how many days back"))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 54)
            Stepper(String(localized: "Amount", comment: "Mac smart album editor: how many days back"),
                    value: Binding(get: { Int(rule.number ?? 30) }, set: { rule.number = Double($0) }), in: 1...36500)
                .labelsHidden()
            // Days / weeks / months / years, as Photos (FS-06.08 §3c); days is stored as nil.
            Picker(String(localized: "Unit", comment: "Smart album date condition: the days/weeks/months/years menu"),
                   selection: Binding(get: { rule.unit ?? .days }, set: { rule.unit = $0 == .days ? nil : $0 })) {
                ForEach(DateUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 96)
        default:
            EmptyView()
        }
    }

    private func datePicker(_ key: WritableKeyPath<SmartAlbumRule, Double?>, label: String) -> some View {
        DatePicker(label, selection: Binding(
            get: { rule[keyPath: key].map { Date(timeIntervalSince1970: $0) } ?? .now },
            set: { rule[keyPath: key] = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        ), displayedComponents: .date)
        .labelsHidden()
        .datePickerStyle(.field)
    }

    private var monthValue: some View {
        let calendar = Calendar.current
        let current = CaptureMonth(containing: rule.number.map { Date(timeIntervalSince1970: $0) } ?? .now)
        let thisYear = calendar.component(.year, from: .now)
        func set(_ part: WritableKeyPath<CaptureMonth, Int>, _ value: Int) {
            var month = current
            month[keyPath: part] = value
            rule.number = month.anchorDate().timeIntervalSince1970
        }
        return HStack(spacing: 6) {
            Picker(String(localized: "Month", comment: "Mac smart album editor: the month of 'is in month'"),
                   selection: Binding(get: { current.month }, set: { set(\.month, $0) })) {
                ForEach(1...12, id: \.self) { Text(calendar.standaloneMonthSymbols[$0 - 1]).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            Picker(String(localized: "Year", comment: "Mac smart album editor: the year of 'is in month'"),
                   selection: Binding(get: { current.year }, set: { set(\.year, $0) })) {
                ForEach((thisYear - 60...thisYear).reversed(), id: \.self) { Text(verbatim: String($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 80)
        }
    }

    // MARK: Folder line

    private var showsFolder: Bool {
        (rule.field == .source || rule.field == .alsoOnServer) && options.folderSources.contains(rule.text)
    }

    /// `Folder  [Shared ▾]  Choose…` under the value (board, FS-19.07 §7).
    private var folderLine: some View {
        let folder = (rule.folder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let all = String(localized: "All Folders", comment: "Smart album Source condition: no folder chosen, the whole source")
        return HStack(spacing: 6) {
            Text("Folder", comment: "Smart album Source condition: the folder row")
                .foregroundStyle(.secondary)
                .frame(width: (isNested ? 116 : 136) + 6 + 128, alignment: .trailing)
            Picker(String(localized: "Folder", comment: "Smart album Source condition: the folder row"),
                   selection: Binding(get: { folder }, set: { rule.folder = $0.isEmpty ? nil : $0 })) {
                Text(all).tag("")
                if !folder.isEmpty { Text(folder).tag(folder) }
            }
            .labelsHidden()
            .frame(width: 170)
            Button(String(localized: "Choose…", comment: "Mac smart album editor: browse the server for the condition's folder"), action: onChooseFolder)
                .frame(width: 80)
                .accessibilityLabel(String(localized: "Choose Folder on \(options.sourceName(rule.text))",
                                           comment: "VoiceOver: browse a server for the smart album condition's folder"))
            Spacer(minLength: 0)
        }
        .frame(height: MacRuleLine.height)
        .padding(.leading, isNested ? 28 : 8)
        .padding(.trailing, 8)
    }

    // MARK: +

    private var addButton: some View {
        let groupHere = addsGroup && !isNested
        return MacRuleLineButton(
            systemImage: groupHere ? "ellipsis" : "plus",
            label: isNested ? String(localized: "Add Condition", comment: "Mac smart album editor: add a condition after this one")
                            : groupHere ? String(localized: "Add Group", comment: "Mac smart album editor: add a nested group of conditions")
                                        : String(localized: "Add Condition", comment: "Mac smart album editor: add a condition after this one"),
            help: isNested ? nil : String(localized: "Add a condition. Hold Option to add a group.",
                                          comment: "Mac smart album editor: the + button's tooltip"),
            action: { groupHere || (!isNested && NSEvent.modifierFlags.contains(.option)) ? onAddGroup() : onAdd() }
        )
        .accessibilityAction(named: Text("Add Group", comment: "Mac smart album editor: add a nested group of conditions")) {
            if !isNested { onAddGroup() }
        }
    }
}

/// The header line of a nested group: `[Any ▾] of the following are true  − +`.
struct MacRuleGroupLine: View {
    @Binding var matchMode: RuleMatchMode
    var onRemove: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker(String(localized: "Group match", comment: "VoiceOver: a nested group's all/any popup"), selection: $matchMode) {
                Text("Any", comment: "Mac smart album group: any of its conditions").tag(RuleMatchMode.any)
                Text("All", comment: "Mac smart album group: all of its conditions").tag(RuleMatchMode.all)
            }
            .labelsHidden()
            .frame(width: 72)
            Text("of the following are true", comment: "Mac smart album group: after Any/All")
            Spacer(minLength: 0)
            MacRuleLineButton(systemImage: "minus", label: String(localized: "Remove Group", comment: "Mac smart album editor: remove a nested group"),
                              action: onRemove)
            MacRuleLineButton(systemImage: "plus", label: String(localized: "Add Condition to Group", comment: "Mac smart album editor: add a condition to a nested group"),
                              action: onAdd)
        }
        .frame(height: MacRuleLine.height)
        .padding(.horizontal, 8)
    }
}

/// The round 20pt − / + of a condition line.
struct MacRuleLineButton: View {
    let systemImage: String
    let label: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(MacTheme.fill, in: Circle())
                .overlay(Circle().strokeBorder(MacTheme.separator, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(help ?? label)
    }
}

/// Five stars; clicking the lit last star clears to none.
struct MacRuleStars: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button { rating = rating == star ? 0 : star } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MarkCopy.starsAccessibility(star))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Rating, \(MarkCopy.starsAccessibility(rating))", comment: "VoiceOver: a smart album rating condition's stars"))
    }
}

/// What the condition lines choose from, read once by the sheet.
struct MacRuleOptions {
    var brands: [String] = []
    var bodies: [String] = []
    var lenses: [String] = []
    var sources: [(value: String, label: String)] = []
    var servers: [(value: String, label: String)] = []
    /// Sources whose folders can be browsed (servers).
    var folderSources: Set<String> = []

    /// Every selectable field — Also on Server too when there is no server,
    /// so the condition can be found before its server is added (AC-247).
    var fields: [RuleField] { RuleField.selectableCases }

    func choices(for field: RuleField) -> [(value: String, label: String)] {
        switch field {
        case .source: sources
        case .alsoOnServer: servers
        default: field.choiceValues
        }
    }

    func sourceName(_ id: String) -> String {
        (servers + sources).first { $0.value == id }?.label ?? ""
    }

    /// Up to 12 indexed values holding what is typed, the typed one left out.
    func suggestions(for field: RuleField, typed: String) -> [String] {
        let all: [String] = switch field {
        case .cameraBrand: brands
        case .cameraBody: bodies
        case .lens: lenses
        default: []
        }
        let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(all.lazy.filter { $0.lowercased().contains(query) && $0.caseInsensitiveCompare(typed) != .orderedSame }.prefix(12))
    }
}
