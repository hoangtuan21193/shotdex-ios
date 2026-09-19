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

    /// Widest a chart card is allowed to get. Roughly an iPad's readable
    /// column; past this the card is mostly whitespace between a label and a
    /// number.
    private static let readableChartWidth: CGFloat = 640

    @ViewBuilder
    private func content(_ model: StatisticsModel) -> some View {
        List {
            if model.hasLoaded && model.totalPhotos == 0 {
                unavailable(
                    "No Indexed Photos",
                    icon: "chart.bar.xaxis",
                    message: "Statistics appear after your library has been indexed."
                )
            } else if model.hasLoaded && model.charts.isEmpty {
                unavailable(
                    "No Charts",
                    icon: "chart.bar.doc.horizontal",
                    message: "Tap + to add a chart to your dashboard."
                )
            } else {
                ForEach(model.charts) { spec in
                    ChartCard(
                        spec: spec,
                        data: model.results[spec.id] ?? [],
                        isLoading: model.isLoading,
                        onEdit: { editorTarget = .edit(spec) },
                        onDuplicate: { model.addChart(duplicate(of: spec)) },
                        onDelete: { model.deleteChart(id: spec.id) },
                        onDrill: { navigation.openLibrary(with: $0) }
                    )
                    // Capped and centred on a wide screen. A chart row stretched
                    // across 835pt — measured on the iPhone Duo's inner display —
                    // puts the bar's label at one edge and its value at the other,
                    // which is a longer eye movement for the same number. Still a
                    // single column, so drag-to-reorder and edit mode are untouched.
                    .frame(maxWidth: Self.readableChartWidth)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // Empty trailing swipe suppresses the synthesized swipe-to-delete;
                    // onDelete still drives the edit-mode red minus button.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {}
                }
                .onMove { model.moveCharts(from: $0, to: $1) }
                .onDelete { model.deleteCharts(at: $0) }
            }

            // Space for the floating chrome (custom bar, pre-iOS 26).
            if #unavailable(iOS 26.0) {
                Color.clear.frame(height: 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
