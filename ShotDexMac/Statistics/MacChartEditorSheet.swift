import SwiftUI

/// New Chart… / Edit Chart (board `MAC_ChartEditor`, FS-07.01b §4, FS-18.04
/// §2): name, chart type, what it groups by and measures, how many, how it
/// splits, its date range, a live preview from the real library, and the
/// conditions — the smart album's condition lines. 640 wide.
struct MacChartEditorSheet: View {
    /// The chart being edited; nil makes a new one.
    let existing: ChartSpec?
    /// The Source popup's source: the preview counts what the card will.
    let sourceId: String?
    let sources: [SourceStore.Source]
    let onSave: (ChartSpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies

    /// The five types of the board, onto the model's four kinds.
    enum ChartType: String, CaseIterable, Identifiable {
        case bars, columns, donut, line, number
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bars: String(localized: "Bars", comment: "Mac chart editor: horizontal bars")
            case .columns: String(localized: "Columns", comment: "Mac chart editor: vertical columns")
            case .donut: String(localized: "Donut", comment: "Mac chart editor: donut chart")
            case .line: String(localized: "Line", comment: "Mac chart editor: line over time")
            case .number: String(localized: "Number", comment: "Mac chart editor: a single number")
            }
        }

        var kind: ChartKind {
            switch self {
            case .bars, .columns: .bar
            case .donut: .donut
            case .line: .line
            case .number: .kpi
            }
        }

        init(_ spec: ChartSpec) {
            switch spec.kind {
            case .donut: self = .donut
            case .line: self = .line
            case .kpi: self = .number
            case .bar: self = MacChartDrawing.drawsColumns(spec) ? .columns : .bars
            }
        }
    }

    @State private var name: String
    @State private var type: ChartType
    @State private var dimension: ChartDimension?
    @State private var aggregation: MetricAggregation
    @State private var field: MetricField?
    @State private var topN: Int
    @State private var seriesSplit: ChartDimension?
    @State private var scope: StatsDateScope
    @State private var query: SmartAlbumQuery
    @State private var options = MacRuleOptions()
    @State private var preview: [ChartDatum]?
    @State private var previewTotal = 0
    @State private var asksDiscard = false
    @State private var previewFailed = false
    @State private var showsHelp = false
    /// What the sheet opened with: Cancel asks only when something moved.
    private let initial: ChartSpec

    init(existing: ChartSpec?, sourceId: String?, sources: [SourceStore.Source], onSave: @escaping (ChartSpec) -> Void) {
        self.existing = existing
        self.sourceId = sourceId
        self.sources = sources
        self.onSave = onSave
        let spec = existing ?? ChartSpec(title: "", kind: .bar, dimension: .cameraBody, topN: 5)
        initial = spec
        _name = State(initialValue: existing?.title ?? "")
        _type = State(initialValue: ChartType(spec))
        _dimension = State(initialValue: spec.dimension)
        // An aggregation the type does not offer (a median bar from elsewhere) opens as a count.
        _aggregation = State(initialValue: spec.kind.allowedAggregations.contains(spec.metric.aggregation) ? spec.metric.aggregation : .count)
        _field = State(initialValue: spec.metric.field)
        _topN = State(initialValue: spec.topN)
        _seriesSplit = State(initialValue: spec.seriesSplit)
        _scope = State(initialValue: spec.scope)
        var query = spec.filter
        if !query.rules.contains(where: { $0.field != .mediaType }) { query.rules.append(SmartAlbumRule()) }
        _query = State(initialValue: query)
    }

    /// What two drafts are compared on: the drawing the type implies, the
    /// conditions that count, the name as saved.
    private static func normalized(_ spec: ChartSpec) -> ChartSpec {
        var spec = spec
        spec.id = ""
        spec.title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.drawsColumns = spec.kind == .bar ? MacChartDrawing.drawsColumns(spec) : nil
        spec.filter.rules = spec.filter.rules.filter { $0.field == .mediaType || $0.isValid }
        return spec
    }

    // MARK: Draft

    /// A Number grouped by something is its biggest group, counted: the
    /// measure has no say then (StatisticsQueries' top group).
    private var countsTopGroup: Bool { type == .number && dimension != nil }

    private var metric: ChartMetric {
        if countsTopGroup { return .photoCount }
        return ChartMetric(aggregation: aggregation, field: aggregation.needsField ? (field ?? .iso) : nil)
    }

    /// The name shown faded in the empty field, and used when it stays empty (C2).
    private var suggestedName: String {
        if let dimension, type != .number { return dimension.displayName }
        if type == .number, dimension == nil { return metric.displayName }
        return dimension?.displayName ?? metric.displayName
    }

    /// The draft as a chart; blank condition lines left out.
    private var draft: ChartSpec {
        var filter = query
        // Blank lines are left out; the chart editor has no folder picker,
        // so a Source condition counts the whole source.
        filter.rules = filter.rules.filter { $0.field == .mediaType || $0.isValid }.map { rule in
            var rule = rule
            rule.folder = nil
            return rule
        }
        var spec = ChartSpec(id: existing?.id ?? initial.id,
                             title: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? suggestedName
                                : name.trimmingCharacters(in: .whitespacesAndNewlines),
                             kind: type.kind, dimension: dimension,
                             metric: metric, filter: filter,
                             seriesSplit: type == .line ? seriesSplit : nil,
                             topN: topN, scope: scope)
        spec.drawsColumns = type == .columns ? true : (type == .bars ? false : nil)
        return spec
    }

    private var isValid: Bool {
        (!type.kind.requiresDimension || dimension != nil) && metric.isValid
            && type.kind.allowedAggregations.contains(aggregation)
    }

    private var isDirty: Bool {
        var a = Self.normalized(draft), b = Self.normalized(initial)
        // A new chart's name is the suggestion until one is typed.
        if existing == nil { b.title = a.title }
        return a != b || (existing == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? String(localized: "New Chart", comment: "Mac chart editor title: a new chart")
                                 : String(localized: "Edit Chart", comment: "Mac chart editor title"))
                .font(.system(size: 15, weight: .semibold))
                .padding(.bottom, 16)
            // Board: Name and Chart Type across the sheet, the preview beside the rest.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                nameRow
                typeRow
            }
            .padding(.bottom, 10)
            HStack(alignment: .top, spacing: 16) {
                form.frame(width: 330, alignment: .leading)
                previewPane.frame(maxWidth: .infinity)
            }
            Divider().padding(.vertical, 14)
            conditions
            footer.padding(.top, 14)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
        .frame(width: 640, height: 560, alignment: .top)
        .background(MacTheme.sheet)
        .task { await loadOptions() }
        .task(id: PreviewKey(spec: Self.normalized(draft).with(title: ""), valid: isValid)) { await recomputePreview() }
        .onChange(of: type) { old, new in clamp(from: old, to: new) }
        // Escape on a sheet dismisses it outright unless taken here: a dirty draft asks first.
        .onExitCommand { cancel() }
        .alert(String(localized: "Discard Changes?", comment: "Mac chart editor: unsaved draft"), isPresented: $asksDiscard) {
            Button(String(localized: "Discard", comment: "Mac chart editor: drop the draft"), role: .destructive) { dismiss() }
            Button(String(localized: "Keep Editing", comment: "Mac chart editor: back to the draft"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Your changes to this chart won't be saved.", comment: "Mac chart editor: what Discard does")
        }
    }

    private var nameRow: some View {
            row(String(localized: "Name:", comment: "Mac chart editor row")) {
                TextField(String(localized: "Name", comment: "Mac chart editor: name field"), text: $name, prompt: Text(suggestedName))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .accessibilityIdentifier("chart.name")
            }
    }

    private var typeRow: some View {
            row(String(localized: "Chart Type:", comment: "Mac chart editor row")) {
                Picker(String(localized: "Chart Type", comment: "Mac chart editor row"), selection: $type) {
                    ForEach(ChartType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("chart.type")
            }
    }

    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            row(String(localized: "Group By:", comment: "Mac chart editor row")) {
                Picker(String(localized: "Group By", comment: "Mac chart editor row"), selection: $dimension) {
                    // A Number may be one figure over every photo.
                    if type == .number {
                        Text("Nothing — one number", comment: "Mac chart editor: a Number with no grouping").tag(ChartDimension?.none)
                    }
                    ForEach(allowedDimensions) { Text($0.displayName).tag(ChartDimension?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
                .accessibilityIdentifier("chart.groupBy")
            }
            row(String(localized: "Measure:", comment: "Mac chart editor row")) {
                HStack(spacing: 6) {
                    // Counting the top group: the picker says so rather than the measure it ignores.
                    Picker(String(localized: "Measure", comment: "Mac chart editor row"),
                           selection: countsTopGroup ? .constant(.count) : $aggregation) {
                        ForEach(MetricAggregation.allCases) { aggregation in
                            Text(MacChartWords.measure(aggregation)).tag(aggregation)
                                // Median of each group has no cheap SQL form: shown, not offered (board).
                                .selectionDisabled(!type.kind.allowedAggregations.contains(aggregation))
                        }
                    }
                    .labelsHidden()
                    .frame(width: aggregation.needsField && !countsTopGroup ? 110 : 200, alignment: .leading)
                    .disabled(countsTopGroup)

                    .accessibilityIdentifier("chart.measure")
                    if aggregation.needsField && !countsTopGroup {
                        Picker(String(localized: "Of", comment: "Mac chart editor: the field a measure runs over"),
                               selection: Binding(get: { field ?? .iso }, set: { field = $0 })) {
                            ForEach(MetricField.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 84, alignment: .leading)
                        .accessibilityIdentifier("chart.of")
                    }
                }
            }
            if countsTopGroup {
                GridRow {
                    Color.clear.frame(width: 84, height: 1)
                    Text("Counts photos in the biggest group.", comment: "Mac chart editor: what a Number grouped by something shows")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if type != .number {
                row(type == .line ? String(localized: "Lines:", comment: "Mac chart editor row: how many lines")
                                  : String(localized: "Show:", comment: "Mac chart editor row: how many groups")) {
                    VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Top", comment: "Mac chart editor: before the number of groups")
                        Text(topN.formatted()).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                        Stepper(String(localized: "Number of items", comment: "Mac chart editor: how many groups or lines"),
                                value: $topN, in: 1...(type == .line ? 6 : 20))
                            .labelsHidden()
                            .accessibilityIdentifier("chart.show")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Number of items", comment: "Mac chart editor: how many groups or lines"))
                    // One line until it is split: nothing to count yet.
                    .disabled(type == .line && seriesSplit == nil)
                    if type == .line && seriesSplit == nil {
                        Text("Split Series first.", comment: "Mac chart editor: why Lines is off").font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }
            }
            row(String(localized: "Split Series:", comment: "Mac chart editor row")) {
                VStack(alignment: .leading, spacing: 2) {
                    Picker(String(localized: "Split Series", comment: "Mac chart editor row"), selection: $seriesSplit) {
                        Text("None", comment: "Mac chart editor: one line").tag(ChartDimension?.none)
                        ForEach(ChartDimension.allCases.filter { $0.axisKind == .categorical }) {
                            Text($0.displayName).tag(ChartDimension?.some($0))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140, alignment: .leading)
                    .disabled(type != .line)
                    .accessibilityIdentifier("chart.split")
                    if type != .line {
                        Text("Line charts only.", comment: "Mac chart editor: why Split Series is off").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            row(String(localized: "Date Range:", comment: "Mac chart editor row")) {
                Picker(String(localized: "Date Range", comment: "Mac chart editor row"), selection: $scope) {
                    ForEach([StatsDateScope.allTime, .thisYear, .thisMonth, .last12Months], id: \.self) { Text($0.title).tag($0) }
                    if case .custom = scope { Text(scope.title).tag(scope) }
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
                .accessibilityIdentifier("chart.range")
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing).frame(width: 84, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var allowedDimensions: [ChartDimension] {
        switch type {
        case .bars: ChartKind.bar.allowedDimensions
        case .columns: ChartKind.bar.allowedDimensions
        case .donut: ChartKind.donut.allowedDimensions
        case .line: ChartKind.line.allowedDimensions
        case .number: ChartKind.kpi.allowedDimensions
        }
    }

    /// A type change keeps what still fits and moves the rest to the first
    /// that does.
    private func clamp(from old: ChartType, to type: ChartType) {
        let allowed = allowedDimensions
        if type == .number {
            // A Number starts as one figure over every photo; grouping is a choice.
            if old != .number { dimension = nil }
            if let dimension, !allowed.contains(dimension) { self.dimension = nil }
        } else if dimension.map({ !allowed.contains($0) }) ?? true {
            dimension = allowed.first
        }
        topN = min(max(topN, 1), type == .line ? 6 : 20)
        if !type.kind.allowedAggregations.contains(aggregation) { aggregation = .count }
        if type != .line { seriesSplit = nil }
    }

    // MARK: Preview

    private struct PreviewKey: Equatable {
        var spec: ChartSpec
        var valid: Bool
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview", comment: "Mac chart editor: the live preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Group {
                if previewFailed {
                    Text("Couldn't load this chart.", comment: "Mac Statistics: a chart's query failed")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140)
                } else if !isValid {
                    Text("Pick what to group by and measure.", comment: "Mac chart editor: preview of an invalid draft")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140)
                } else if draft.kind == .kpi {
                    MacKPITile(spec: draft, data: preview, showsMenu: false) { EmptyView() }
                } else {
                    MacChartCardPreview(spec: draft, data: preview, total: previewTotal, sourceName: sourceName(draft))
                }
            }
            .allowsHitTesting(false)
            // Twenty bars do not fit: the preview scrolls rather than cuts them off.
            .frame(maxWidth: .infinity, alignment: .top)
            .modifier(MacPreviewScroll())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Preview", comment: "Mac chart editor: the live preview"))
    }

    private func sourceName(_ spec: ChartSpec) -> String? {
        spec.filter.pinnedSourceId.flatMap { id in sources.first { $0.id == id }?.name }
    }

    /// The draft's data, read off the main actor a moment after the last change.
    private func recomputePreview() async {
        previewFailed = false
        // The last data belongs to the last spec: a spinner until the new one is read.
        preview = nil
        guard isValid else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let spec = draft
        let queries = StatisticsQueries(database: dependencies.database, sourceId: sourceId)
        let result = await Task.detached(priority: .userInitiated) {
            (data: try? queries.chartData(for: spec, scope: spec.scope), total: (try? queries.totalPhotos(scope: spec.scope)) ?? 0)
        }.value
        guard !Task.isCancelled else { return }
        previewFailed = result.data == nil
        preview = result.data
        previewTotal = result.total
    }

    // MARK: Conditions

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Conditions", comment: "Mac chart editor: the conditions section").fontWeight(.semibold)
                Spacer()
                Picker(String(localized: "Media Type", comment: "Mac chart editor: photos, videos or both"), selection: mediaKind) {
                    Text("All", comment: "Mac chart editor media type: photos and videos").tag(MediaKind?.none)
                    ForEach(MediaKind.allCases) { kind in Text(kind.displayName).tag(MediaKind?.some(kind)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .accessibilityIdentifier("chart.media")
                Text("Match", comment: "Mac chart editor: before all/any").foregroundStyle(.secondary)
                Picker(String(localized: "Match", comment: "Mac chart editor: before all/any"), selection: $query.matchMode) {
                    Text("all", comment: "Chart conditions match mode").tag(RuleMatchMode.all)
                    Text("any", comment: "Chart conditions match mode").tag(RuleMatchMode.any)
                }
                .labelsHidden()
                .frame(width: 64)
                .accessibilityIdentifier("chart.match")
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(query.rules.filter { $0.field != .mediaType }) { rule in
                        MacRuleLine(rule: ruleBinding(rule), options: options, allowsGroups: false,
                                    onChooseFolder: {},
                                    onRemove: { removeRule(rule.id) },
                                    onAdd: { addRule(after: rule.id) },
                                    onAddGroup: { addRule(after: rule.id) })
                        Divider()
                    }
                }
            }
            .frame(height: 80)
            .background(MacTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Conditions", comment: "Mac chart editor: the conditions section"))
            if query.rules.contains(where: { $0.field != .mediaType && !$0.isValid && !$0.text.isEmpty }) {
                Text("Incomplete conditions are left out.", comment: "Mac chart editor: a half-filled condition line")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var mediaKind: Binding<MediaKind?> {
        Binding(
            get: { query.rules.first { $0.field == .mediaType && $0.op == .isExactly }.flatMap { MediaKind(rawValue: $0.text) } },
            set: { kind in
                query.rules.removeAll { $0.field == .mediaType && $0.op == .isExactly }
                guard let kind else { return }
                query.rules.insert(SmartAlbumRule(field: .mediaType, op: .isExactly, text: kind.rawValue), at: 0)
            }
        )
    }

    private func ruleBinding(_ rule: SmartAlbumRule) -> Binding<SmartAlbumRule> {
        Binding(get: { query.rules.first { $0.id == rule.id } ?? rule },
                set: { new in if let index = query.rules.firstIndex(where: { $0.id == rule.id }) { query.rules[index] = new } })
    }

    private func removeRule(_ id: UUID) {
        query.rules.removeAll { $0.id == id }
        if !query.rules.contains(where: { $0.field != .mediaType }) { query.rules.append(SmartAlbumRule()) }
    }

    private func addRule(after id: UUID) {
        let row = query.rules.firstIndex { $0.id == id }
        var rule = row.map { SmartAlbumRule(field: query.rules[$0].field) } ?? SmartAlbumRule()
        MacRuleLine.seed(&rule, options: options)
        query.rules.insert(rule, at: row.map { $0 + 1 } ?? query.rules.endIndex)
    }

    private func loadOptions() async {
        var options = MacRuleOptions()
        options.sources = sources.filter { $0.kind != "server" }.map { ($0.id, $0.name) }
        options.servers = sources.filter { $0.kind == "server" }.map { ($0.id, $0.name) }
        let catalog = await dependencies.filterSuggestions.load()
        options.brands = catalog.brands
        options.bodies = catalog.bodies
        options.lenses = catalog.lenses
        self.options = options
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { showsHelp.toggle() } label: {
                Image(systemName: "questionmark").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                    .background(MacTheme.fill, in: Circle())
                    .overlay(Circle().strokeBorder(MacTheme.separator))
                    .contentShape(Circle())
            }
                .buttonStyle(.plain)
                .help(String(localized: "How charts work", comment: "Mac chart editor: help"))
                .accessibilityLabel(String(localized: "Help", comment: "Mac chart editor: help"))
                .accessibilityIdentifier("chart.help")
                .popover(isPresented: $showsHelp, arrowEdge: .top) {
                    Text("Group By picks what each bar or slice is; Measure picks what it shows. Conditions narrow the photos the chart counts; a Source condition keeps the chart on that source whatever the Source popup says.",
                         comment: "Mac chart editor: help text")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).frame(width: 300).padding(14)
                }
            Spacer()
            Button { cancel() } label: { Text("Cancel", comment: "Mac sheet: cancel").frame(minWidth: 72) }
                .keyboardShortcut(.cancelAction)
            Button {
                onSave(draft)
                dismiss()
            } label: { Text("Save", comment: "Mac chart editor: save the chart").frame(minWidth: 72) }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
            .help(isValid ? "" : String(localized: "Pick what to group by and measure.", comment: "Mac chart editor: why Save is off"))
            .accessibilityIdentifier("chart.save")
        }
    }

    private func cancel() {
        if isDirty { asksDiscard = true } else { dismiss() }
    }
}

enum MacChartWords {
    /// The Measure menu's words (board): Photo Count · Average · … · Slow Shutter Rate.
    static func measure(_ aggregation: MetricAggregation) -> String {
        switch aggregation {
        case .count: String(localized: "Photo Count", comment: "Mac chart editor measure")
        case .average: String(localized: "Average", comment: "Mac chart editor measure")
        case .median: String(localized: "Median", comment: "Mac chart editor measure")
        case .sum: String(localized: "Sum", comment: "Mac chart editor measure")
        case .min: String(localized: "Minimum", comment: "Mac chart editor measure")
        case .max: String(localized: "Maximum", comment: "Mac chart editor measure")
        case .slowShutterShare: String(localized: "Slow Shutter Rate", comment: "Mac chart editor measure")
        }
    }
}

/// How a `.bar` chart is drawn on the Mac.
enum MacChartDrawing {
    /// The editor's choice, else the axis: names as rows, numbers as columns.
    static func drawsColumns(_ spec: ChartSpec) -> Bool {
        if let choice = spec.drawsColumns { return choice }
        return spec.dimension.map { $0.axisKind != .categorical } ?? false
    }
}

private extension ChartSpec {
    func with(title: String) -> ChartSpec {
        var spec = self
        spec.title = title
        return spec
    }
}

/// The preview pane: up to 250 tall, scrolling past that.
private struct MacPreviewScroll: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView { content }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 250)
    }
}
