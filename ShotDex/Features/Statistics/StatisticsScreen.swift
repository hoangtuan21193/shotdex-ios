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

    /// Card width the multi-column dashboard is built from. The minimum is
    /// what a bar chart needs before its labels start truncating; the maximum
    /// stops a card from turning into a label at one edge and a number at the
    /// other. Between them, `.adaptive` gives two columns on an unfolded Duo
    /// or a portrait iPad and three on a landscape one.
    private static let chartCardWidth: ClosedRange<CGFloat> = 320...520

    private static let cardSpacing: CGFloat = 16

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
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: Self.chartCardWidth.lowerBound,
                            maximum: Self.chartCardWidth.upperBound
                        ),
                        spacing: Self.cardSpacing,
                        alignment: .top
                    )
                ],
                alignment: .center,
                spacing: Self.cardSpacing
            ) {
                ForEach(model.charts) { spec in
                    card(spec, model: model)
                        // Cards in a row are as tall as the tallest of them, so
                        // the background has to stretch or the shorter ones
                        // float in a gap.
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, Self.cardSpacing)
            .padding(.vertical, 8)
            floatingChromeSpacer
        }
        .scrollContentBackground(.hidden)
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

            floatingChromeSpacer
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
