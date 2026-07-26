import SwiftUI

/// Creates or edits a dashboard chart. The user picks a chart type, an X-axis
/// dimension (group-by), a Y-axis metric (aggregation), and optional
/// conditions — the same rule builder as smart albums (`RuleBuilderSections`).
/// A live preview renders the chart as configured. Saving hands a fully-formed
/// `ChartSpec` back to the caller (which persists via `StatisticsModel`).
struct ChartEditorSheet: View {
    /// Non-nil when editing (reuses the spec's id).
    var existing: ChartSpec?
    let dependencies: AppDependencies
    /// Oldest capture date in the index — bounds the custom range picker.
    let earliestDate: Date?
    var onSave: (ChartSpec) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var kind: ChartKind
    @State private var dimension: ChartDimension?
    @State private var aggregation: MetricAggregation
    @State private var field: MetricField
    @State private var seriesSplit: ChartDimension?
    @State private var topN: Int
    @State private var filter: SmartAlbumQuery
    /// This chart's own date range.
    @State private var scope: StatsDateScope

    /// Stable id so the preview and the saved spec agree while editing.
    @State private var specID: String

    @State private var availableBrands: [String] = []
    @State private var availableBodies: [String] = []
    @State private var availableLenses: [String] = []
    @State private var previewData: [ChartDatum] = []
    @State private var previewLoading = false
    @State private var isRangePickerPresented = false

    init(
        existing: ChartSpec?,
        dependencies: AppDependencies,
        earliestDate: Date?,
        onSave: @escaping (ChartSpec) -> Void
    ) {
        self.existing = existing
        self.dependencies = dependencies
        self.earliestDate = earliestDate
        self.onSave = onSave

        let seed = existing ?? ChartSpec(title: "", kind: .bar, dimension: .cameraBody)
        _title = State(initialValue: seed.title)
        _kind = State(initialValue: seed.kind)
        _dimension = State(initialValue: seed.dimension)
        _aggregation = State(initialValue: seed.metric.aggregation)
        _field = State(initialValue: seed.metric.field ?? .iso)
        _seriesSplit = State(initialValue: seed.seriesSplit)
        _topN = State(initialValue: seed.topN)
        _filter = State(initialValue: seed.filter)
        _scope = State(initialValue: seed.scope)
        _specID = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    // MARK: Derived

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metric: ChartMetric {
        ChartMetric(aggregation: aggregation, field: aggregation == .count ? nil : field)
    }

    /// The spec as currently configured (validated rules only).
    private var draft: ChartSpec {
        ChartSpec(
            id: specID,
            title: trimmedTitle.isEmpty ? defaultTitle : trimmedTitle,
            kind: kind,
            dimension: kind.requiresDimension ? dimension : dimension,
            metric: metric,
            filter: SmartAlbumQuery(matchMode: filter.matchMode, rules: filter.validRules),
            seriesSplit: kind == .line ? seriesSplit : nil,
            topN: topN,
            scope: scope
        )
    }

    /// A sensible auto-title from the dimension + metric when none is typed.
    private var defaultTitle: String {
        if let dimension {
            return dimension.displayName
        }
        return metric.displayName
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
            && (!kind.requiresDimension || dimension != nil)
            && metric.isValid
    }

    var body: some View {
        NavigationStack {
            List {
                typeSection
                dataSection
                if kind != .donut {
                    metricSection
                }
                if kind == .line {
                    seriesSection
                }
                if kind == .bar || kind == .donut {
                    limitSection
                }
                RuleBuilderSections(
                    query: $filter,
                    brands: availableBrands,
                    bodies: availableBodies,
                    lenses: availableLenses,
                    matchCount: nil
                )
                dateRangeSection
                previewSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(existing == nil ? "New Chart" : "Edit Chart")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRangePickerPresented) {
                DateRangePickerSheet(
                    earliestDate: earliestDate,
                    initialRange: customDays
                ) { days in
                    scope = .custom(days: days)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: draft) { _, _ in runPreview() }
    }

    // MARK: Sections

    private var typeSection: some View {
        Section {
            TextField(defaultTitle, text: $title)
            Picker("Chart Type", selection: $kind) {
                ForEach(ChartKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                }
            }
            .onChange(of: kind) { _, new in applyKind(new) }
        } header: {
            Text("Chart")
        }
    }

    private var dataSection: some View {
        Section {
            Picker("Group by", selection: $dimension) {
                if !kind.requiresDimension {
                    Text("Whole library").tag(ChartDimension?.none)
                }
                ForEach(kind.allowedDimensions) { dimension in
                    Text(dimension.displayName).tag(ChartDimension?.some(dimension))
                }
            }
        } header: {
            Text(kind == .line ? "X-Axis (time)" : "X-Axis")
        } footer: {
            if kind == .kpi {
                Text(dimension == nil
                     ? "Shows a single value across the whole library."
                     : "Shows the top group by photo count.")
            }
        }
    }

    private var metricSection: some View {
        Section {
            Picker("Measure", selection: $aggregation) {
                ForEach(kind.allowedAggregations) { aggregation in
                    Text(aggregation.displayName).tag(aggregation)
                }
            }
            if aggregation != .count {
                Picker("Of", selection: $field) {
                    ForEach(MetricField.allCases) { field in
                        Text(field.displayName).tag(field)
                    }
                }
            }
        } header: {
            Text("Y-Axis")
        }
    }

    private var seriesSection: some View {
        Section {
            Picker("Split into series by", selection: $seriesSplit) {
                Text("None").tag(ChartDimension?.none)
                ForEach(ChartDimension.allCases.filter { $0.axisKind == .categorical }) { dimension in
                    Text(dimension.displayName).tag(ChartDimension?.some(dimension))
                }
            }
            if seriesSplit != nil {
                Stepper("Top \(topN) series", value: $topN, in: 2...8)
            }
        } header: {
            Text("Series")
        }
    }

    private var limitSection: some View {
        Section {
            Stepper("Show top \(topN)", value: $topN, in: 3...20)
        } header: {
            Text("Buckets")
        } footer: {
            Text("Limits how many bars/slices appear.")
        }
    }

    /// The current custom range as dates, so re-opening the picker restores it.
    private var customDays: ClosedRange<Date>? {
        guard case .custom(let seconds) = scope else { return nil }
        let lower = Date(timeIntervalSince1970: TimeInterval(seconds.lowerBound))
        let upper = Date(timeIntervalSince1970: TimeInterval(seconds.upperBound))
        return lower...upper
    }

    private var dateRangeSection: some View {
        Section {
            rangeButton("All Time", scope: .allTime)
            rangeButton("This Year", scope: .thisYear)
            rangeButton("This Month", scope: .thisMonth)
            Button {
                isRangePickerPresented = true
            } label: {
                let isCustom = if case .custom = scope { true } else { false }
                HStack {
                    Text("Custom Range…").foregroundStyle(Color(.label))
                    Spacer()
                    if isCustom {
                        Text(scope.title).foregroundStyle(.secondary)
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Date Range")
        }
    }

    private func rangeButton(_ title: String, scope newScope: StatsDateScope) -> some View {
        Button {
            scope = newScope
        } label: {
            HStack {
                Text(title).foregroundStyle(Color(.label))
                Spacer()
                if scope == newScope {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }

    private var previewSection: some View {
        Section {
            if canSave {
                ChartContentView(spec: draft, data: previewData, isLoading: previewLoading, onDrill: nil)
            } else {
                Text("Finish configuring the chart to see a preview.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Preview")
        }
    }

    // MARK: Behavior

    /// Keeps the config valid when the chart type changes: clamps the
    /// dimension, aggregation, and series to what the new kind allows.
    private func applyKind(_ new: ChartKind) {
        if new.requiresDimension {
            if dimension == nil || !new.allowedDimensions.contains(dimension!) {
                dimension = new.allowedDimensions.first
            }
        }
        if !new.allowedAggregations.contains(aggregation) {
            aggregation = new.allowedAggregations.first ?? .count
        }
        if new != .line { seriesSplit = nil }
    }

    private func prepare() {
        let queries = dependencies.libraryQueries
        availableBrands = (try? queries.distinctCameraBrands()) ?? []
        availableBodies = (try? queries.distinctCameraBodies()) ?? []
        availableLenses = (try? queries.distinctLenses()) ?? []
        runPreview()
    }

    private func runPreview() {
        guard canSave else {
            previewData = []
            return
        }
        let spec = draft
        let queries = dependencies.statisticsQueries
        let scope = self.scope
        previewLoading = true
        Task.detached(priority: .userInitiated) {
            let data = (try? queries.chartData(for: spec, scope: scope)) ?? []
            await MainActor.run {
                previewData = data
                previewLoading = false
            }
        }
    }
}
