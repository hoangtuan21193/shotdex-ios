import Charts
import SwiftUI

/// Statistics (board `MAC_Statistics`, FS-18.04 §2, FS-07): Insights, the
/// row of numbers, then the chart cards in columns. Each card keeps its own
/// range; the Source popup narrows every card for as long as it is set.
/// Clicking a bar or a row opens the Library on those photos.
struct MacStatisticsScreen: View {
    /// The window's sources, as the sidebar lists them: the Source popup.
    let sources: [SourceStore.Source]
    /// A Top Camera row opened its camera's page (board `MAC_StatisticsCamera`).
    /// Held by the window: Back from the Library returns to it.
    @Binding var camera: MacStatisticsCameraModel?
    /// The Library on the photos of a bar, a row or an insight, in the
    /// source the popup has.
    let open: (FilterCriteria, String?) -> Void

    @Environment(MacDependencies.self) private var dependencies
    @State private var model: MacStatisticsModel?
    @State private var deleting: ChartSpec?
    /// New Chart… / Edit Chart…: the editor sheet (board `MAC_ChartEditor`).
    @State private var editing: EditRequest?
    /// A chart just saved: scrolled into view.
    @State private var scrollTarget: String?

    struct EditRequest: Identifiable {
        let id = UUID()
        var spec: ChartSpec?
    }
    /// Settings › Show Insights in Statistics (FS-07.02 §1).
    @AppStorage(SettingsKeys.showsInsights) private var showsInsights = true

    var body: some View {
        Group {
            if let model, model.failedToLoad {
                ContentUnavailableView {
                    Label(String(localized: "Can't Load Statistics", comment: "Mac Statistics: the chart list could not be read"),
                          systemImage: "chart.bar")
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Statistics: read the charts again")) { model.reload() }
                }
            } else if let model, model.hasLoaded, model.totalPhotos == 0 {
                ContentUnavailableView(String(localized: "No Photos Indexed", comment: "Mac Statistics: empty library"),
                                       systemImage: "chart.bar",
                                       description: Text("Add a source in the sidebar; its photos are counted here once they are read.",
                                                         comment: "Mac Statistics: empty library, what to do"))
            } else if let model, model.hasLoaded, model.charts.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Charts", comment: "Mac Statistics: every chart deleted"), systemImage: "chart.bar")
                } description: {
                    Text("Add one with +, or bring back the standard set.", comment: "Mac Statistics: every chart deleted")
                } actions: {
                    Button(String(localized: "Restore Default Charts", comment: "Mac Statistics: add the Mac's standard charts back")) {
                        model.restoreDefaults()
                    }
                }
            } else if let camera {
                MacStatisticsCameraPage(model: camera, open: { open($0, camera.sourceId) },
                                        showAllSources: { model?.sourceId = nil })
            } else if let model, model.hasLoaded {
                content(model)
                    // A Source change reads every card again: the old numbers dim meanwhile.
                    .opacity(model.isReloading ? 0.55 : 1)
                    .animation(.easeOut(duration: 0.15), value: model.isReloading)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacTheme.content)
        .navigationTitle(camera == nil ? String(localized: "Statistics", comment: "Mac Statistics title") : "")
        .navigationSubtitle(camera == nil ? subtitle : "")
        .toolbar { toolbar }
        .task {
            guard model == nil else { return }
            let model = MacStatisticsModel(database: dependencies.database)
            // Back from the Library to a camera page: the popup says the page's source.
            model.sourceId = camera?.sourceId
            self.model = model
            model.reload()
        }
        // A source read, added or removed since: the counts follow.
        // The popup is the one source of truth: a removed source, "Show All Sources", a pick.
        .onChange(of: model?.sourceId) { _, id in camera?.setSource(id) }
        // Only a source added or removed: a read's progress in a row is not a reason.
        .onChange(of: Set(sources.map(\.id))) { _, ids in model?.keep(sourceIds: ids) }
        .sheet(item: $editing) { request in
            MacChartEditorSheet(existing: request.spec, sourceId: model?.sourceId, sources: sources) { spec in
                if request.spec == nil {
                    scrollTarget = model?.add(spec)
                } else {
                    model?.update(spec)
                    scrollTarget = spec.id
                }
            }
        }
        .confirmationDialog(String(localized: "Delete “\(deleting?.title ?? "")”?", comment: "Mac Statistics: confirm deleting a chart"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { chart in
            Button(String(localized: "Delete Chart", comment: "Mac Statistics: delete a chart"), role: .destructive) {
                model?.delete(chart.id)
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
        } message: { _ in
            Text("Only the chart goes; no photo changes.",
                 comment: "Mac Statistics: what deleting a chart does")
        }
    }

    private var subtitle: String {
        guard let model, model.hasLoaded else { return "" }
        let photos = max(0, model.totalPhotos - model.totalVideos)
        var parts = [String(AttributedString(localized: "^[\(photos) photo](inflect: true)",
                                             comment: "Mac Statistics subtitle: photos counted").characters)]
        if model.totalVideos > 0 {
            parts.append(String(AttributedString(localized: "^[\(model.totalVideos) video](inflect: true)",
                                                 comment: "Mac Statistics subtitle: videos counted").characters))
        }
        return parts.joined(separator: " · ") + " — " + StatisticsQueries.sourceFootnote
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if camera != nil {
            ToolbarItem(placement: .navigation) {
                Button { camera = nil } label: {
                    Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help(String(localized: "Back to Statistics", comment: "Mac Statistics camera page: Back"))
                .accessibilityIdentifier("camera.back")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let model {
                Picker(selection: Binding(get: { model.sourceId ?? "" }, set: { model.sourceId = $0.isEmpty ? nil : $0 })) {
                    Text("All Sources", comment: "Mac Statistics: Source popup, every source").tag("")
                    Divider()
                    ForEach(sources, id: \.id) { source in
                        Text(source.name).tag(source.id)
                    }
                } label: {
                    Text("Source", comment: "Mac Statistics: Source popup")
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help(String(localized: "Count the photos with a copy in one source", comment: "Mac Statistics: Source popup tooltip"))
                .accessibilityIdentifier("statistics.source")

                if let camera {
                    Button {
                        open(camera.criteria, camera.sourceId)
                    } label: {
                        Label(String(localized: "Show in Library", comment: "Mac Statistics camera page: the camera's photos in All Photos"),
                              systemImage: "photo.on.rectangle")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("camera.showInLibrary")
                } else {
                Menu {
                    Button(String(localized: "New Chart…", comment: "Mac Statistics: + menu, open the chart editor")) {
                        editing = EditRequest(spec: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    Section(String(localized: "Add Chart", comment: "Mac Statistics: + menu header")) {
                        if model.addable.isEmpty {
                            Text("Every chart is on the board", comment: "Mac Statistics: + menu, nothing left to add")
                        }
                        ForEach(model.addable, id: \.title) { spec in
                            Button(MacStatisticsWords.title(spec)) { model.add(spec) }
                        }
                    }
                } label: {
                    Label(String(localized: "Add Chart", comment: "Mac Statistics: + button"), systemImage: "plus")
                }
                .help(String(localized: "Add Chart", comment: "Mac Statistics: + button"))
                .accessibilityIdentifier("statistics.add")
                }
            }
        }
    }

    // MARK: Content

    private func content(_ model: MacStatisticsModel) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsInsights {
                        MacInsightsStrip(load: model.insights) { open($0, model.sourceId) }
                    }
                    // Board: 12 between the numbers and the cards, 16 above.
                    VStack(alignment: .leading, spacing: 12) {
                        if !model.kpis.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(model.kpis, id: \.id) { spec in
                                    MacKPITile(spec: spec, data: model.results[spec.id],
                                               sourceName: spec.filter.pinnedSourceId.flatMap { id in sources.first { $0.id == id }?.name }) {
                                        menu(spec, model: model)
                                    }
                                    .id(spec.id)
                                }
                            }
                        }
                        columns(model, width: geometry.size.width - 32)
                    }
                }
                .padding(16)
            }
            // The chart just saved is where the eye goes next.
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    scrollTarget = nil
                }
            }
            }
        }
    }

    /// Four columns at 1440 (board), fewer as the window narrows; each card
    /// goes to the shortest column so far, in order.
    private func columns(_ model: MacStatisticsModel, width: CGFloat) -> some View {
        let count = max(1, min(4, Int((width + 12) / (260 + 12))))
        var heights = Array(repeating: 0.0, count: count)
        var buckets = Array(repeating: [ChartSpec](), count: count)
        for spec in model.cards {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            buckets[column].append(spec)
            heights[column] += MacStatisticsWords.estimatedHeight(spec) + 12
        }
        return HStack(alignment: .top, spacing: 12) {
            ForEach(buckets.indices, id: \.self) { column in
                VStack(spacing: 12) {
                    ForEach(buckets[column], id: \.id) { spec in
                        card(spec, model: model) {
                            MacChartCardBody(spec: spec, data: model.results[spec.id], failed: model.failedCharts.contains(spec.id),
                                             total: model.scopeTotals[spec.id] ?? 0, open: { open($0, model.sourceId) },
                                             openCamera: { key, name in
                                                 let page = MacStatisticsCameraModel(model: key, name: name, database: dependencies.database,
                                                                                     sourceId: model.sourceId)
                                                 camera = page
                                                 page.load()
                                             })
                        }
                        .id(spec.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func card<Body: View>(_ spec: ChartSpec, model: MacStatisticsModel, @ViewBuilder body: @escaping () -> Body) -> some View {
        MacChartCard(spec: spec, sourceName: spec.filter.pinnedSourceId.flatMap { id in sources.first { $0.id == id }?.name },
                     menu: { menu(spec, model: model) }, content: body)
    }

    @ViewBuilder
    private func menu(_ spec: ChartSpec, model: MacStatisticsModel) -> some View {
            Button(String(localized: "Edit Chart…", comment: "Mac Statistics: chart menu, open the editor")) {
                editing = EditRequest(spec: spec)
            }
            Button(String(localized: "Duplicate", comment: "Mac Statistics: chart menu")) { model.duplicate(spec.id) }
            Divider()
            Button(String(localized: "Move Earlier", comment: "Mac Statistics: chart menu")) { model.move(spec.id, earlier: true) }
                .disabled(!model.canMove(spec.id, earlier: true))
            Button(String(localized: "Move Later", comment: "Mac Statistics: chart menu")) { model.move(spec.id, earlier: false) }
                .disabled(!model.canMove(spec.id, earlier: false))
            Divider()
            Button(String(localized: "Delete Chart…", comment: "Mac Statistics: chart menu"), role: .destructive) { deleting = spec }
    }
}

// MARK: - Insights

/// Board `MAC_Statistics`: one row of up to three sentences, the unknown-
/// sensor note on the right; a sentence with a filter opens those photos.
private struct MacInsightsStrip: View {
    let load: MacStatisticsModel.InsightsLoad
    let open: (FilterCriteria) -> Void

    var body: some View {
        switch load {
        case .loading:
            frame { ProgressView().controlSize(.small) }
        case .failed:
            frame { Text("Couldn't compute insights.", comment: "Mac Statistics: Insights failed").foregroundStyle(.secondary) }
        case .loaded(.hidden):
            EmptyView()
        case .loaded(.belowThreshold(let count)):
            frame { Text(InsightCopy.belowThreshold(count)).foregroundStyle(.secondary) }
        case .loaded(.insights(let insights, let unknown)):
            frame(unknown: unknown) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { index, insight in
                        if index > 0 {
                            Rectangle().fill(MacTheme.separator).frame(width: 1).padding(.horizontal, 16)
                        }
                        row(insight)
                    }
                }
            }
        }
    }

    private func frame(unknown: Int? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Insights", comment: "Mac Statistics: the Insights card title")
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let unknown {
                    Text(InsightCopy.unknownSensorFooter(unknown))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Insights", comment: "Mac Statistics: the Insights card title"))
    }

    @ViewBuilder
    private func row(_ insight: Insight) -> some View {
        let sentence = InsightCopy.sentence(insight)
        let label = HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: insight.systemImage).font(.system(size: 15)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(sentence).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if insight.filter != nil {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        if let filter = insight.filter {
            Button { open(filter) } label: { label }
                .buttonStyle(.plain)
                .help(String(localized: "Show these photos", comment: "Mac Statistics: insight tooltip"))
                .accessibilityLabel(sentence)
        } else {
            label.accessibilityElement(children: .ignore).accessibilityLabel(sentence)
        }
    }
}

// MARK: - Card

/// One card: title, its range under it, a ⋯ menu on hover, the body.
struct MacChartCard<Menu: View, Content: View>: View {
    let spec: ChartSpec
    /// A card with its own Source condition says which (FS-18.04 §2): the
    /// popup does not move it.
    var sourceName: String?
    var showsMenu = true
    @ViewBuilder let menu: () -> Menu
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(MacStatisticsWords.title(spec)).fontWeight(.semibold).lineLimit(1)
                    if spec.kind != .kpi {
                        Text([spec.scope.title, sourceName].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if showsMenu { MacChartMenuButton(spec: spec, isShown: isHovered, menu: menu) }
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacStatisticsWords.title(spec))
    }
}

/// A number of the top row (board): its name small, the value big, its
/// range on the right; the ⋯ menu on hover.
struct MacKPITile<Menu: View>: View {
    let spec: ChartSpec
    let data: [ChartDatum]?
    /// A number with its own Source condition says which.
    var sourceName: String?
    /// The editor's preview has no menu.
    var showsMenu = true
    @ViewBuilder let menu: () -> Menu
    @State private var isHovered = false

    var body: some View {
        let value = data.map { $0.first.map { MacStatisticsWords.kpiValue($0.value, spec: spec) } ?? "—" } ?? "…"
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(MacStatisticsWords.title(spec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(MacStatisticsWords.title(spec))
                Spacer(minLength: 2)
                if showsMenu { MacChartMenuButton(spec: spec, isShown: isHovered, menu: menu) }
            }
            HStack(alignment: .lastTextBaseline) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.2)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 4)
                // A Number grouped by something names its biggest group.
                Text([spec.dimension != nil ? data?.first?.label : nil, spec.scope.title, sourceName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacStatisticsWords.title(spec))
        .accessibilityValue([value, spec.scope.title, sourceName].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A card's ⋯: always there for the keyboard and VoiceOver, drawn on hover.
private struct MacChartMenuButton<Menu: View>: View {
    let spec: ChartSpec
    let isShown: Bool
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        let name = String(localized: "Options for \(MacStatisticsWords.title(spec))", comment: "Mac Statistics: a card's ⋯ menu")
        SwiftUI.Menu(content: menu) {
            // The label names the menu (a plain glyph reads "More").
            Label(name, systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 22, height: 22)
                // Clear, not faded: a faded label leaves the accessibility tree.
                .foregroundStyle(isShown ? Color.primary : Color.clear)
                .background(isShown ? MacTheme.fill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        // A SwiftUI-drawn label (the AppKit pop-up button draws its own
        // image and ignores the fade).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .help(String(localized: "Chart Options", comment: "Mac Statistics: a card's ⋯ menu"))
        .accessibilityLabel(name)
        .accessibilityIdentifier("statistics.options." + spec.title)
    }
}

/// The body of a chart card, by the shape of its data.
struct MacChartCardBody: View {
    let spec: ChartSpec
    let data: [ChartDatum]?
    let failed: Bool
    let total: Int
    let open: (FilterCriteria) -> Void
    /// A Top Camera row opens its camera's page, not the Library.
    var openCamera: ((String, String) -> Void)?

    var body: some View {
        if failed {
            Text("Couldn't load this chart.", comment: "Mac Statistics: a chart's query failed")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else if let data {
            loaded(data)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    @ViewBuilder
    private func loaded(_ data: [ChartDatum]) -> some View {
        let known = data.filter { !$0.isUnknown }
        if known.isEmpty {
            Text("No photos in this range.", comment: "Mac Statistics: an empty chart")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else if spec.kind == .line {
            MacLineChart(spec: spec, data: known)
        } else if spec.kind == .donut, let dimension = spec.dimension {
            MacDonutChart(dimension: dimension, scope: spec.scope, data: known, total: total, open: open)
        } else if let dimension = spec.dimension, !MacChartDrawing.drawsColumns(spec) {
            MacRankRows(spec: spec, dimension: dimension, data: known, total: total, open: open, openCamera: openCamera)
        } else if let dimension = spec.dimension {
            MacColumnChart(spec: spec, dimension: dimension, data: known, open: open)
        }
        if let footnote = MacStatisticsWords.footnote(spec, data: data, total: total) {
            Text(footnote).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Top Camera, Top Lens, Body + Lens: name, count, share and a bar under it;
/// the first in the accent, the rest in its soft tint.
private struct MacRankRows: View {
    let spec: ChartSpec
    let dimension: ChartDimension
    let data: [ChartDatum]
    let total: Int
    let open: (FilterCriteria) -> Void
    var openCamera: ((String, String) -> Void)?

    var body: some View {
        let top = data.map(\.value).max() ?? 1
        VStack(spacing: 6) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, datum in
                let criteria = datum.drillKey.flatMap { dimension.drillCriteria(key: $0) }
                let share = total > 0 ? datum.value / Double(total) : 0
                let row = VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(datum.label).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Text(Int(datum.value).formatted()).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                    GeometryReader { geometry in
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(index == 0 ? MacTheme.accent : MacTheme.chartSoft)
                            .frame(width: max(4, geometry.size.width * datum.value / top))
                    }
                    .frame(height: 7)
                }
                .contentShape(Rectangle())
                let words = MacStatisticsWords.rowLabel(datum, share: share)
                if dimension == .cameraBody, let key = datum.drillKey, let openCamera {
                    // A chevron says this row opens a page, not the Library.
                    Button { openCamera(key, datum.label) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            row
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .help(String(localized: "Show this camera's statistics", comment: "Mac Statistics: a Top Camera row opens its page"))
                        .accessibilityLabel(words)
                        .accessibilityHint(String(localized: "Show this camera's statistics", comment: "Mac Statistics: a Top Camera row opens its page"))
                } else if let criteria {
                    Button { open(criteria) } label: { row }
                        .buttonStyle(.plain)
                        .help(MacStatisticsWords.clickHelp(datum.value, scope: spec.scope))
                        .accessibilityLabel(words)
                        .accessibilityHint(MacStatisticsWords.clickHelp(datum.value, scope: spec.scope))
                } else {
                    row.accessibilityElement(children: .ignore).accessibilityLabel(words)
                }
            }
        }
    }
}

/// ISO, focal length, aperture, shutter, weekday, time of day: columns in
/// the soft tint, the tallest in the accent with its number; hovering one
/// says how many, clicking opens them.
struct MacColumnChart: View {
    let spec: ChartSpec
    let dimension: ChartDimension
    let data: [ChartDatum]
    let open: (FilterCriteria) -> Void
    @State private var hovered: String?

    var body: some View {
        let peak = data.max { $0.value < $1.value }?.id
        let hour = dimension == .hourOfDay
        // Hour and weekday cannot be opened yet (no such Library filter): no hover light.
        let lit = hovered.flatMap { label in data.first { $0.label == label && Self.opens($0, dimension) }?.id }
        Chart(data) { datum in
            // Board: columns at most 24 wide, air between them.
            BarMark(x: .value("Group", datum.label), y: .value("Photos", datum.value),
                    width: hour ? .fixed(3) : .fixed(data.count > 8 ? 16 : 24))
                .foregroundStyle(datum.id == peak || datum.id == lit ? MacTheme.accent : MacTheme.chartSoft)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: hour ? 1 : 4, topTrailingRadius: hour ? 1 : 4))
                .annotation(position: .top, spacing: 2) {
                    if datum.id == peak {
                        Text(Int(datum.value).formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
                    }
                }
        }
        .chartYAxis {
            // The baseline only (board: a 1px `sep` rule).
            AxisMarks(values: [0]) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(MacTheme.separator) }
        }
        .chartXAxis {
            AxisMarks { value in
                if let label = value.as(String.self), Self.showsLabel(label, in: data, hour: hour) {
                    // Long bins ("Slower than 1/30s") drop a neighbour rather than overlap it.
                    AxisValueLabel(collisionResolution: .greedy) {
                        Text(hour ? Self.short(label, hour: true) : MacStatisticsWords.binLabel(label, dimension: dimension)).font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hovered = label(at: point, proxy: proxy, geometry: geometry)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { point in
                        guard let label = label(at: point, proxy: proxy, geometry: geometry),
                              let datum = data.first(where: { $0.label == label }), datum.value > 0,
                              let key = datum.drillKey, let criteria = dimension.drillCriteria(key: key) else { return }
                        open(criteria)
                    }
                if let hovered, let datum = data.first(where: { $0.label == hovered }) {
                    if let plotFrame = proxy.plotFrame {
                    MacChartTooltip(title: "\(MacStatisticsWords.groupName(spec, label: datum.label)) · "
                                        + String(AttributedString(localized: "^[\(Int(datum.value)) photo](inflect: true)",
                                                                  comment: "Mac Statistics tooltip: photos in a column").characters),
                                    detail: Self.opens(datum, dimension) ? MacStatisticsWords.clickHelp(datum.value, scope: spec.scope) : nil)
                        .fixedSize()
                        .position(x: min(max(80, (proxy.position(forX: datum.label) ?? 0) + geometry[plotFrame].origin.x), geometry.size.width - 80),
                                  y: 14)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 112)
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(data) { datum in
                Rectangle().accessibilityLabel(
                    "\(MacStatisticsWords.groupName(spec, label: datum.label)), "
                    + String(AttributedString(localized: "^[\(Int(datum.value)) photo](inflect: true)",
                                              comment: "Mac Statistics: photos in a column, VoiceOver").characters))
            }
        }
    }

    static func opens(_ datum: ChartDatum, _ dimension: ChartDimension) -> Bool {
        datum.value > 0 && datum.drillKey.flatMap { dimension.drillCriteria(key: $0) } != nil
    }

    private func label(at point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let frame = proxy.plotFrame else { return nil }
        let plot = geometry[frame]
        // The axis labels' margin is not a column.
        guard plot.contains(point) else { return nil }
        let x = point.x - plot.origin.x
        // The column under the pointer, or the nearest one in a thin-column chart.
        if let label: String = proxy.value(atX: x) { return label }
        return data.min { abs((proxy.position(forX: $0.label) ?? .infinity) - x) < abs((proxy.position(forX: $1.label) ?? .infinity) - x) }?.label
    }

    /// Every label of a short axis; on Time of Day only 0, 6, 12 and 18.
    static func showsLabel(_ label: String, in data: [ChartDatum], hour: Bool) -> Bool {
        guard hour else { return data.count <= 6 || (data.firstIndex { $0.label == label } ?? 0).isMultiple(of: 2) }
        return ["0", "6", "12", "18"].contains(short(label, hour: true))
    }

    static func short(_ label: String, hour: Bool) -> String {
        guard hour else { return label }
        return String(label.prefix { $0 != ":" })
    }
}

/// Photos per Month (one line per camera, legend under it) and Photos per
/// Year (one line over a soft area).
private struct MacLineChart: View {
    let spec: ChartSpec
    let data: [ChartDatum]

    var body: some View {
        // At most six series, in their fixed colours (DESIGN.md §3.4).
        let series = Array((Array(NSOrderedSet(array: data.compactMap(\.series))) as? [String] ?? []).prefix(MacTheme.chartSeries.count))
        let periods = Set(data.map(\.label)).count
        VStack(alignment: .leading, spacing: 8) {
            Chart(data) { datum in
                if series.isEmpty {
                    AreaMark(x: .value("Period", datum.label), y: .value("Photos", datum.value))
                        .foregroundStyle(MacTheme.chartArea)
                    LineMark(x: .value("Period", datum.label), y: .value("Photos", datum.value))
                        .foregroundStyle(MacTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    if periods == 1 {
                        PointMark(x: .value("Period", datum.label), y: .value("Photos", datum.value))
                            .foregroundStyle(MacTheme.accent).symbolSize(20)
                    }
                } else {
                    LineMark(x: .value("Period", datum.label), y: .value("Photos", datum.value))
                        .foregroundStyle(by: .value("Series", datum.series ?? ""))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    // A line of one point draws nothing: the dot stands in.
                    if periods == 1 {
                        PointMark(x: .value("Period", datum.label), y: .value("Photos", datum.value))
                            .foregroundStyle(by: .value("Series", datum.series ?? ""))
                            .symbolSize(20)
                    }
                }
            }
            .chartForegroundStyleScale(domain: series, range: Array(MacTheme.chartSeries.prefix(max(1, series.count))))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        Text(value.as(String.self).map(MacStatisticsWords.periodLabel) ?? "").font(.caption2)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: value.as(Double.self) == 0 ? [] : [3, 3]))
                        .foregroundStyle(MacTheme.separator)
                    AxisValueLabel().font(.caption2)
                }
            }
            .frame(height: 120)
            if !series.isEmpty {
                MacFlowLayout(spacing: 8) {
                    ForEach(Array(series.enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 5) {
                            Circle().fill(MacTheme.chartSeries[index]).frame(width: 8, height: 8)
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A dark rounded label over a column: what it is, and that a click opens it.
private struct MacChartTooltip: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold))
            if let detail { Text(detail).font(.caption2) }
        }
        .foregroundStyle(MacTheme.onChartTip)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MacTheme.chartTip, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Words

enum MacStatisticsWords {
    /// A bin's axis label as the board writes it — its lower bound: "28–34"
    /// → "28", "f/1.0 – 2.0" → "1.0", "≤ 100" → "100", "> 6400" → "6400+".
    /// The tooltip keeps the whole range.
    static func binLabel(_ label: String, dimension: ChartDimension) -> String {
        guard [.iso, .aperture, .focalActual, .focalEquivalent].contains(dimension),
              let range = label.range(of: "[0-9]+(\\.[0-9]+)?", options: .regularExpression) else { return label }
        let number = String(label[range])
        return label.hasPrefix(">") || label.hasSuffix("+") ? number + "+" : number
    }

    /// A line chart's period as the axis says it: "2026-09" → "Sep",
    /// "2026" → "'26" (board `MAC_Statistics`).
    static func periodLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
           let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) {
            return date.formatted(.dateTime.month(.abbreviated))
        }
        if parts.count == 1, key.count == 4 { return "'" + key.suffix(2) }
        return key
    }

    /// A chart's title as the user reads it: the default ones localized.
    static func title(_ spec: ChartSpec) -> String {
        String(localized: String.LocalizationValue(spec.title), comment: "Mac Statistics: a chart's title")
    }

    static func kpiValue(_ value: Double, spec: ChartSpec) -> String {
        if spec.metric.aggregation == .count { return Int(value.rounded()).formatted() }
        return ChartValueFormatter.string(value, metric: spec.metric)
    }

    /// The Library has no date-range filter yet: a card of This Year opens
    /// the group from every date, and says so instead of a count.
    static func clickHelp(_ count: Double, scope: StatsDateScope) -> String {
        guard scope == .allTime else {
            return String(localized: "Click to show these photos from all dates",
                          comment: "Mac Statistics: a row or column of a dated card opens its group over all time")
        }
        return String(AttributedString(localized: "Click to show ^[\(Int(count)) photo](inflect: true)",
                                       comment: "Mac Statistics: a column or row opens its photos").characters)
    }

    static func rowLabel(_ datum: ChartDatum, share: Double) -> String {
        "\(datum.label), " + String(AttributedString(localized: "^[\(Int(datum.value)) photo](inflect: true)",
                                                     comment: "Mac Statistics: photos in a row, VoiceOver").characters)
            + ", " + share.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "ISO 8000+", "28–34mm", "1/400 – 1/125 s": the group as the tooltip says it.
    static func groupName(_ spec: ChartSpec, label: String) -> String {
        switch spec.dimension {
        case .iso: "ISO " + label
        case .focalActual, .focalEquivalent: label.hasSuffix("mm") ? label : label + "mm"
        default: label
        }
    }

    /// Under a card: the photos it leaves out — other values, or no value.
    static func footnote(_ spec: ChartSpec, data: [ChartDatum], total: Int) -> String? {
        guard spec.kind != .line, spec.metric.aggregation == .count, let dimension = spec.dimension else { return nil }
        let unknown = Int(data.filter(\.isUnknown).map(\.value).reduce(0, +))
        let shown = Int(data.filter { !$0.isUnknown }.map(\.value).reduce(0, +))
        if dimension.axisKind == .categorical {
            let rest = max(0, total - shown)
            guard rest > 0 else { return nil }
            return String(AttributedString(localized: "^[\(rest) photo](inflect: true) from other values or without this info.",
                                           comment: "Mac Statistics: photos a top-N card does not show").characters)
        }
        guard unknown > 0 else { return nil }
        return String(AttributedString(localized: "^[\(unknown) photo](inflect: true) without this info.",
                                       comment: "Mac Statistics: photos with no value for this chart").characters)
    }

    /// The column layout's guess at a card's height before it is drawn.
    /// From the chart's definition, not its data: cards keep their column
    /// while data arrives.
    static func estimatedHeight(_ spec: ChartSpec) -> Double {
        let header = 52.0
        if spec.kind == .line { return header + 150 + (spec.seriesSplit != nil ? 24 : 0) }
        if let dimension = spec.dimension, dimension.axisKind == .categorical {
            return header + Double(max(1, spec.topN)) * 34 + 24
        }
        return header + 140 + 20
    }
}

/// A donut (FS-07.01b §1): slices in the six series colours, the seventh
/// and later grey; a legend of rows under it that open their photos.
private struct MacDonutChart: View {
    let dimension: ChartDimension
    let scope: StatsDateScope
    let all: [ChartDatum]
    let total: Int
    let open: (FilterCriteria) -> Void

    init(dimension: ChartDimension, scope: StatsDateScope, data: [ChartDatum], total: Int, open: @escaping (FilterCriteria) -> Void) {
        self.dimension = dimension
        self.scope = scope
        all = data
        self.total = total
        self.open = open
    }

    /// Six colours, never cycled (DESIGN.md §3.4): the seventh and later are
    /// one grey "Other" slice, not drillable.
    private var data: [ChartDatum] {
        let limit = MacTheme.chartSeries.count
        guard all.count > limit else { return all }
        let rest = all.dropFirst(limit - 1).map(\.value).reduce(0, +)
        return Array(all.prefix(limit - 1)) + [ChartDatum(label: String(localized: "Other", comment: "Mac Statistics donut: the slices past the sixth"),
                                                         value: rest, drillKey: nil)]
    }

    private func color(_ index: Int) -> Color {
        index < MacTheme.chartSeries.count && !(all.count > MacTheme.chartSeries.count && index == MacTheme.chartSeries.count - 1)
            ? MacTheme.chartSeries[index] : Color.secondary.opacity(0.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(Array(data.enumerated()), id: \.element.id) { index, datum in
                SectorMark(angle: .value("Photos", datum.value), innerRadius: .ratio(0.6), angularInset: 1)
                    .foregroundStyle(color(index))
            }
            .frame(height: 120)
            .accessibilityHidden(true)
            ForEach(Array(data.enumerated()), id: \.element.id) { index, datum in
                let share = total > 0 ? datum.value / Double(total) : 0
                let row = HStack(spacing: 6) {
                    Circle().fill(color(index)).frame(width: 8, height: 8)
                    Text(datum.label).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Int(datum.value).formatted()).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit().frame(width: 30, alignment: .trailing)
                }
                .contentShape(Rectangle())
                if let criteria = datum.drillKey.flatMap({ dimension.drillCriteria(key: $0) }) {
                    Button { open(criteria) } label: { row }
                        .buttonStyle(.plain)
                        .help(MacStatisticsWords.clickHelp(datum.value, scope: scope))
                        .accessibilityLabel(MacStatisticsWords.rowLabel(datum, share: share))
                } else {
                    row.accessibilityElement(children: .ignore).accessibilityLabel(MacStatisticsWords.rowLabel(datum, share: share))
                }
            }
        }
    }
}

/// The editor's live preview: the card as the dashboard will draw it.
struct MacChartCardPreview: View {
    let spec: ChartSpec
    let data: [ChartDatum]?
    let total: Int
    var sourceName: String?

    var body: some View {
        MacChartCard(spec: spec, sourceName: sourceName, showsMenu: false, menu: { EmptyView() }) {
            MacChartCardBody(spec: spec, data: data, failed: false, total: total, open: { _ in })
        }
        // A picture of the card: nothing in it to press or read twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Preview of \(spec.title)", comment: "Mac chart editor: the preview, VoiceOver"))
    }
}
