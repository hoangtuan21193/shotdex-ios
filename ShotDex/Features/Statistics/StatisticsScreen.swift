import SwiftUI

/// Statistics tab: a customizable dashboard of chart widgets. Charts are
/// user-defined (type + X-axis dimension + Y-axis metric + condition filter),
/// reorderable and editable; a first-run install is seeded with defaults.
struct StatisticsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var controller: StatsController?
    @State private var editMode: EditMode = .inactive
    @State private var editorTarget: EditorTarget?

    /// Which editor to present: a brand-new chart or an existing one.
    private enum EditorTarget: Identifiable {
        case new
        case edit(ChartWidget)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let widget): widget.id
            }
        }

        var existing: ChartWidget? {
            switch self {
            case .new: nil
            case .edit(let widget): widget
            }
        }
    }

    var body: some View {
        Group {
            if let controller {
                content(controller)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsDrawerButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add chart")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !(controller?.charts.isEmpty ?? true) {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: {
                        Image(systemName: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                            .font(.callout)
                    }
                    .accessibilityLabel(editMode.isEditing ? "Done" : "Reorder charts")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(item: $editorTarget) { target in
            if let controller {
                ChartEditorSheet(
                    existing: target.existing,
                    dependencies: dependencies,
                    earliestDate: controller.earliestDate
                ) { widget in
                    switch target {
                    case .new: controller.addChart(widget)
                    case .edit: controller.updateChart(widget)
                    }
                }
            }
        }
        .task {
            if controller == nil {
                controller = StatsController(dependencies: dependencies)
            }
            controller?.load()
        }
    }

    @ViewBuilder
    private func content(_ controller: StatsController) -> some View {
        List {
            if controller.hasLoaded && controller.totalPhotos == 0 {
                unavailable(
                    "No Indexed Photos",
                    icon: "chart.bar.xaxis",
                    message: "Statistics appear after your library has been indexed."
                )
            } else if controller.hasLoaded && controller.charts.isEmpty {
                unavailable(
                    "No Charts",
                    icon: "chart.bar.doc.horizontal",
                    message: "Tap + to add a chart to your dashboard."
                )
            } else {
                ForEach(controller.charts) { widget in
                    ChartCard(
                        widget: widget,
                        data: controller.results[widget.id] ?? [],
                        isLoading: controller.isLoading,
                        onEdit: { editorTarget = .edit(widget) },
                        onDuplicate: { controller.addChart(duplicate(of: widget)) },
                        onDelete: { controller.deleteChart(id: widget.id) },
                        onDrill: { navigation.openLibrary(with: $0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // Empty trailing swipe suppresses the synthesized swipe-to-delete;
                    // onDelete still drives the edit-mode red minus button.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {}
                }
                .onMove { controller.moveCharts(from: $0, to: $1) }
                .onDelete { controller.deleteCharts(at: $0) }
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

    /// A copy of a widget with a fresh id and a "Copy" suffix.
    private func duplicate(of widget: ChartWidget) -> ChartWidget {
        ChartWidget(
            id: UUID().uuidString,
            title: "\(widget.title) Copy",
            kind: widget.kind,
            dimension: widget.dimension,
            metric: widget.metric,
            filter: widget.filter,
            seriesSplit: widget.seriesSplit,
            topN: widget.topN,
            scope: widget.scope
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
