import SwiftUI

/// Statistics tab: a customizable dashboard of charts. Charts are
/// user-defined (type + X-axis dimension + Y-axis metric + condition filter),
/// reorderable and editable; a first-run install is seeded with defaults.
struct StatisticsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var model: StatisticsModel?
    @State private var editMode: EditMode = .inactive
    @State private var editorTarget: EditorTarget?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Which editor to present: a brand-new chart or an existing one.
    private enum EditorTarget: Identifiable {
        case new
        case edit(ChartSpec)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let spec): spec.id
            }
        }

        var existing: ChartSpec? {
            switch self {
            case .new: nil
            case .edit(let spec): spec
            }
        }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsButton()
            }
            // Reorder first, then a spacer, so "+" sits on its own Liquid Glass
            // capsule at the trailing edge instead of sharing one with it.
            ToolbarItem(placement: .topBarTrailing) {
                if !(model?.charts.isEmpty ?? true) {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: {
                        Image(systemName: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                            .font(.callout)
                    }
                    .tint(.primary)
                    .accessibilityLabel(editMode.isEditing ? "Done" : "Reorder charts")
                }
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .tint(.primary)
                .accessibilityLabel("Add chart")
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(item: $editorTarget) { target in
            if let model {
                ChartEditorSheet(
                    existing: target.existing,
                    dependencies: dependencies,
                    earliestDate: model.earliestDate
                ) { spec in
                    switch target {
                    case .new: model.addChart(spec)
                    case .edit: model.updateChart(spec)
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = StatisticsModel(dependencies: dependencies)
            }
            model?.load()
        }
    }

    /// Narrowest a chart card may be: below this a bar chart's labels start
    /// truncating. Three columns are the ceiling — wider than that and a card
    /// is a label at one edge and a number at the other.
    private static let minimumCardWidth: CGFloat = 320
    private static let maximumColumnCount = 3

    private static let cardSpacing: CGFloat = 16

    /// Air below the last card, so the dashboard does not end against the
    /// floating tab bar.
    private static let bottomClearance: CGFloat = 48

    /// Columns that fit `width` at `minimumCardWidth`, clamped to 2...3 —
    /// `usesColumns` already guarantees a regular-width screen, which is
    /// always wide enough for two.
    private static func columnCount(forWidth width: CGFloat) -> Int {
        let usable = width - cardSpacing // the outer margins
        let fits = Int((usable + cardSpacing) / (minimumCardWidth + cardSpacing))
        return min(maximumColumnCount, max(2, fits))
    }

    /// Charts lay out in columns on a wide screen, and in a reorderable list
    /// everywhere else. Edit mode falls back to the list on every size class:
    /// drag-to-reorder and the red delete minus are `List` affordances, and
    /// reordering a grid by eye is worse than reordering a column anyway.
    private var usesColumns: Bool {
        horizontalSizeClass == .regular && !editMode.isEditing
    }

    @ViewBuilder
    private func content(_ model: StatisticsModel) -> some View {
        Group {
            if model.hasLoaded && model.totalPhotos == 0 {
                ContentUnavailableView(
                    "No Indexed Photos",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Statistics appear after your library has been indexed.")
                )
            } else if model.hasLoaded && model.charts.isEmpty {
                ContentUnavailableView(
                    "No Charts",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Tap + to add a chart to your dashboard.")
                )
            } else if usesColumns {
                columns(model)
            } else {
                rows(model)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func columns(_ model: StatisticsModel) -> some View {
        GeometryReader { proxy in
            let count = Self.columnCount(forWidth: proxy.size.width)
            ScrollView {
                // Independent columns, not a `LazyVGrid`: a grid gives every
                // row the height of its tallest card, so a KPI next to a bar
                // chart leaves a hole the height of the bar chart. Charts are
                // dealt round-robin, which keeps reading order and lets each
                // column close up behind a short card.
                HStack(alignment: .top, spacing: Self.cardSpacing) {
                    ForEach(0..<count, id: \.self) { column in
                        LazyVStack(spacing: Self.cardSpacing) {
                            ForEach(Self.charts(model.charts, inColumn: column, of: count)) { spec in
                                card(spec, model: model)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, Self.cardSpacing)
                .padding(.top, 8)
                floatingChromeSpacer
                Color.clear.frame(height: Self.bottomClearance)
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// The charts dealt to one column, round-robin.
    private static func charts(
        _ charts: [ChartSpec], inColumn column: Int, of count: Int
    ) -> [ChartSpec] {
        charts.enumerated().compactMap { $0.offset % count == column ? $0.element : nil }
    }

    private func rows(_ model: StatisticsModel) -> some View {
        List {
            ForEach(model.charts) { spec in
                card(spec, model: model)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // Empty trailing swipe suppresses the synthesized swipe-to-delete;
                    // onDelete still drives the edit-mode red minus button.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {}
            }
            .onMove { model.moveCharts(from: $0, to: $1) }
            .onDelete { model.deleteCharts(at: $0) }

            // Air below the last card plus, pre-iOS 26, the custom bar's own
            // height — the list's bottom inset stops at the tab bar, so
            // without this the last chart sits against it.
            floatingChromeSpacer
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            Color.clear.frame(height: Self.bottomClearance)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func card(_ spec: ChartSpec, model: StatisticsModel) -> some View {
        ChartCard(
            spec: spec,
            data: model.results[spec.id] ?? [],
            isLoading: model.isLoading,
            onEdit: { editorTarget = .edit(spec) },
            onDuplicate: { model.addChart(duplicate(of: spec)) },
            onDelete: { model.deleteChart(id: spec.id) },
            onDrill: { navigation.openLibrary(with: $0) }
        )
    }

    /// Space for the floating chrome (custom bar, pre-iOS 26).
    @ViewBuilder
    private var floatingChromeSpacer: some View {
        if #unavailable(iOS 26.0) {
            Color.clear.frame(height: 60)
        }
    }

    /// A copy of a spec with a fresh id and a "Copy" suffix.
    private func duplicate(of spec: ChartSpec) -> ChartSpec {
        ChartSpec(
            id: UUID().uuidString,
            title: "\(spec.title) Copy",
            kind: spec.kind,
            dimension: spec.dimension,
            metric: spec.metric,
            filter: spec.filter,
            seriesSplit: spec.seriesSplit,
            topN: spec.topN,
            scope: spec.scope
        )
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    return NavigationStack {
        StatisticsScreen()
    }
    .environment(dependencies)
    .environment(dependencies.photoLibrary)
    .environment(AppNavigation())
}
