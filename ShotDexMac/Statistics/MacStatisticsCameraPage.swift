import Charts
import SwiftUI

/// One camera's page (board `MAC_StatisticsCamera`, FS-18.04 §2): opened
/// from a Top Camera row. What it shot, with which lenses, how, and its
/// best photos — the same Source popup as the dashboard narrows it.
@MainActor
@Observable
final class MacStatisticsCameraModel {
    /// The normalized model a Top Camera row carries, and its name there.
    let model: String
    let name: String

    private(set) var profile: StatisticsQueries.CameraProfile?
    private(set) var libraryTotal = 0
    private(set) var months: [ChartDatum] = []
    private(set) var medianISO: Double?
    private(set) var slowShutter: Double?
    private(set) var lenses: [ChartDatum] = []
    private(set) var focal: [ChartDatum] = []
    private(set) var aperture: [ChartDatum] = []
    private(set) var iso: [ChartDatum] = []
    private(set) var topRated: [LibraryGridItem] = []
    private(set) var topRatedCount = 0
    private(set) var hasLoaded = false
    private(set) var failed = false
    /// A Source change reads again: the page dims meanwhile.
    private(set) var isReloading = false

    var topRatedSort: SortOption = .dateTakenNewest {
        didSet { if topRatedSort != oldValue { loadTopRated() } }
    }
    @ObservationIgnored private var topRatedRequest = 0

    @ObservationIgnored private var generation = 0
    private let database: AppDatabase
    /// The Source popup's source while this page reads.
    private(set) var sourceId: String?
    private(set) var topRatedFailed = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(model: String, name: String, database: AppDatabase, sourceId: String?) {
        self.model = model
        self.name = name
        self.database = database
        self.sourceId = sourceId
    }

    /// The camera as a Library filter: Show in Library, a bar's photos.
    var criteria: FilterCriteria {
        var criteria = FilterCriteria()
        criteria.cameraBodies = [model]
        return criteria
    }

    var topRatedCriteria: FilterCriteria {
        var criteria = self.criteria
        criteria.ratingFilter = .atLeast(5)
        return criteria
    }

    /// The 5-star photos as a query, narrowed by the Source popup like the
    /// rest of the page.
    private var topRatedQuery: SmartAlbumQuery {
        var rules = [SmartAlbumRule(field: .cameraBody, op: .isExactly, text: model),
                     SmartAlbumRule(field: .rating, op: .equalTo, number: 5)]
        if let sourceId { rules.append(SmartAlbumRule(field: .source, op: .isExactly, text: sourceId)) }
        return SmartAlbumQuery(rules: rules)
    }

    private var filter: SmartAlbumQuery {
        SmartAlbumQuery(rules: [SmartAlbumRule(field: .cameraBody, op: .isExactly, text: model)])
    }

    func setSource(_ id: String?) {
        guard id != sourceId else { return }
        sourceId = id
        load()
    }

    /// Every number and chart in one pass off the main actor.
    func load() {
        generation += 1
        let generation = self.generation
        isReloading = hasLoaded
        let queries = StatisticsQueries(database: database, sourceId: sourceId)
        let filter = self.filter
        let model = self.model
        task?.cancel()
        task = Task.detached(priority: .userInitiated) { [weak self] in
            // Any query that fails fails the page (Try Again), rather than a
            // tile that says 0 or a chart that says "no photos".
            do {
                func data(_ spec: ChartSpec) throws -> [ChartDatum] { try queries.chartData(for: spec, scope: spec.scope) }
                func value(_ metric: ChartMetric) throws -> Double? {
                    try data(ChartSpec(title: "", kind: .kpi, dimension: nil, metric: metric, filter: filter)).first?.value
                }
                let result = Loaded(
                    profile: try queries.cameraProfile(model: model),
                    libraryTotal: try queries.totalPhotos(scope: .allTime),
                    months: try data(ChartSpec(title: "", kind: .line, dimension: .dateMonth, filter: filter)),
                    medianISO: try value(ChartMetric(aggregation: .median, field: .iso)),
                    slowShutter: try value(.slowShutterShare),
                    lenses: try data(ChartSpec(title: "", kind: .bar, dimension: .lens, filter: filter, topN: 5)),
                    focal: try data(ChartSpec(title: "", kind: .bar, dimension: .focalEquivalent, filter: filter)),
                    aperture: try data(ChartSpec(title: "", kind: .bar, dimension: .aperture, filter: filter)),
                    iso: try data(ChartSpec(title: "", kind: .bar, dimension: .iso, filter: filter)))
                await self?.apply(result, generation: generation)
            } catch {
                await self?.fail(generation)
            }
        }
        loadTopRated()
    }

    private struct Loaded: Sendable {
        var profile: StatisticsQueries.CameraProfile
        var libraryTotal: Int
        var months, lenses, focal, aperture, iso: [ChartDatum]
        var medianISO, slowShutter: Double?

        init(profile: StatisticsQueries.CameraProfile, libraryTotal: Int, months: [ChartDatum], medianISO: Double?,
             slowShutter: Double?, lenses: [ChartDatum], focal: [ChartDatum], aperture: [ChartDatum], iso: [ChartDatum]) {
            self.profile = profile
            self.libraryTotal = libraryTotal
            self.months = months
            self.medianISO = medianISO
            self.slowShutter = slowShutter
            self.lenses = lenses
            self.focal = focal
            self.aperture = aperture
            self.iso = iso
        }
    }

    private func apply(_ loaded: Loaded, generation: Int) {
        guard generation == self.generation else { return }
        profile = loaded.profile
        libraryTotal = loaded.libraryTotal
        months = loaded.months
        medianISO = loaded.medianISO
        slowShutter = loaded.slowShutter
        lenses = loaded.lenses
        focal = loaded.focal
        aperture = loaded.aperture
        iso = loaded.iso
        failed = false
        isReloading = false
        hasLoaded = true
    }

    private func fail(_ generation: Int) {
        guard generation == self.generation else { return }
        failed = true
        isReloading = false
        hasLoaded = true
    }

    /// The 5-star photos, newest first unless Sort By says otherwise.
    private func loadTopRated() {
        topRatedRequest += 1
        let request = topRatedRequest
        let queries = LibraryQueries(database: database)
        let query = topRatedQuery
        let sort = topRatedSort
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let items = try await queries.gridItems(matching: query, sort: sort, limit: 8)
                let count = try await queries.count(matching: query)
                await self?.applyTopRated(items, count: count, failed: false, request: request)
            } catch {
                await self?.applyTopRated([], count: 0, failed: true, request: request)
            }
        }
    }

    func retryTopRated() { loadTopRated() }

    private func applyTopRated(_ items: [LibraryGridItem], count: Int, failed: Bool, request: Int) {
        // Only the newest request lands: a source or sort picked meanwhile wins.
        guard request == topRatedRequest else { return }
        topRatedFailed = failed
        topRated = items
        topRatedCount = count
    }

    /// Busiest month: its key ("2026-08") and count.
    var busiestMonth: ChartDatum? { months.max { $0.value < $1.value } }
}

/// The page itself.
struct MacStatisticsCameraPage: View {
    let model: MacStatisticsCameraModel
    let open: (FilterCriteria) -> Void
    /// "Show All Sources": the Source popup back to All Sources.
    var showAllSources: () -> Void = {}
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if model.failed {
                ContentUnavailableView {
                    Label(String(localized: "Can't Load \(model.name)", comment: "Mac Statistics camera page: the queries failed"),
                          systemImage: "camera")
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Statistics: read again")) { model.load() }
                }
            } else if model.hasLoaded, let profile = model.profile, profile.photos == 0 {
                ContentUnavailableView {
                    Label(String(localized: "No Photos from \(model.name) Here", comment: "Mac Statistics camera page: the source has none of this camera's photos"),
                          systemImage: "camera")
                } description: {
                    Text("The source picked in the toolbar has none of this camera's photos.",
                         comment: "Mac Statistics camera page: empty in this source")
                } actions: {
                    Button(String(localized: "Show All Sources", comment: "Mac Statistics camera page: Source back to All Sources"), action: showAllSources)
                }
            } else if model.hasLoaded, let profile = model.profile {
                pageContent(profile)
                    .opacity(model.isReloading ? 0.55 : 1)
                    .animation(.easeOut(duration: 0.15), value: model.isReloading)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacTheme.content)
    }

    private func pageContent(_ profile: StatisticsQueries.CameraProfile) -> some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(profile)
                        tiles(profile)
                        HStack(alignment: .top, spacing: 12) {
                            frames.frame(maxWidth: .infinity)
                            lensCard(profile).frame(width: 380)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            columnCard(String(localized: "Focal Length", comment: "Mac Statistics camera page card"),
                                       detail: String(localized: "All Time · equals equivalent on Full Frame", comment: "Mac Statistics camera page: focal card subtitle"),
                                       data: model.focal, dimension: .focalEquivalent)
                            columnCard(String(localized: "Aperture", comment: "Mac Statistics camera page card"),
                                       detail: StatsDateScope.allTime.title, data: model.aperture, dimension: .aperture)
                            columnCard(String(localized: "ISO", comment: "Mac Statistics camera page card"),
                                       detail: StatsDateScope.allTime.title, data: model.iso, dimension: .iso)
                        }
                        topRated
                    }
                    .padding(16)
                }
    }

    // MARK: Header

    private func header(_ profile: StatisticsQueries.CameraProfile) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.system(size: 22, weight: .bold)).lineLimit(1)
                Text(MacCameraWords.subtitle(profile)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                // Open: the window switches now; not open yet: it takes the pane as it appears.
                MacSettingsPane.pending = .cameras
                NotificationCenter.default.post(name: .macSettingsShowPane, object: MacSettingsPane.cameras.rawValue)
                openSettings()
            } label: {
                Label(String(localized: "Camera Database…", comment: "Mac Statistics camera page: open Settings › Cameras"), systemImage: "camera")
            }
            .help(String(localized: "Sensor size and crop of each camera", comment: "Mac Statistics camera page: Camera Database tooltip"))
            .accessibilityIdentifier("camera.database")
        }
        .accessibilityElement(children: .contain)
    }

    private func tiles(_ profile: StatisticsQueries.CameraProfile) -> some View {
        let share = model.libraryTotal > 0 ? Double(profile.photos) / Double(model.libraryTotal) : 0
        let busiest = model.busiestMonth
        return HStack(spacing: 12) {
            tile(String(localized: "Photos", comment: "Mac Statistics camera page tile"), profile.photos.formatted(),
                 aside: model.sourceId == nil
                    ? String(localized: "\(share.formatted(.percent.precision(.fractionLength(0)))) of library",
                             comment: "Mac Statistics camera page: the camera's share of the library")
                    : String(localized: "\(share.formatted(.percent.precision(.fractionLength(0)))) of this source",
                             comment: "Mac Statistics camera page: the camera's share of the source in the popup"))
            tile(String(localized: "Lenses Used", comment: "Mac Statistics camera page tile"), profile.lenses.formatted())
            tile(String(localized: "Busiest Month", comment: "Mac Statistics camera page tile"),
                 busiest.map { MacCameraWords.monthYear($0.label) } ?? "—",
                 short: busiest.map { MacCameraWords.monthYear($0.label, short: true) },
                 aside: busiest.map { Int($0.value).formatted() })
            tile(String(localized: "Median ISO", comment: "Mac Statistics camera page tile"),
                 model.medianISO.map { ChartValueFormatter.string($0, metric: ChartMetric(aggregation: .median, field: .iso)) } ?? "—")
            tile(String(localized: "Slow Shutter", comment: "Mac Statistics camera page tile"),
                 model.slowShutter.map { ChartValueFormatter.string($0, metric: .slowShutterShare) } ?? "—")
            tile(String(localized: "Favorites", comment: "Mac Statistics camera page tile"), profile.favorites.formatted())
        }
    }

    private func tile(_ title: String, _ value: String, short: String? = nil, aside: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            // Narrow tiles: the short value, then no aside, before any ellipsis.
            ViewThatFits(in: .horizontal) {
                valueLine(value, aside: aside)
                valueLine(short ?? value, aside: aside)
                valueLine(short ?? value, aside: nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func valueLine(_ value: String, aside: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 22, weight: .bold)).tracking(-0.2).monospacedDigit().lineLimit(1).fixedSize()
            if let aside { Text(aside).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize() }
        }
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// Frames in Library: photos per month as columns, the running total as
    /// a blue line over them (scaled to the columns; its last value labelled).
    private var frames: some View {
        let months = model.months
        let peak = months.max { $0.value < $1.value }
        let top = max(1, peak?.value ?? 1)
        let totals = months.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1.value) }
        let scale = top / max(1, totals.last ?? 1)
        return card(String(localized: "Frames in Library", comment: "Mac Statistics camera page card"), detail: StatsDateScope.allTime.title) {
            if months.isEmpty {
                Text("No dated photos.", comment: "Mac Statistics camera page: no capture dates").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart {
                    ForEach(months) { month in
                        // A few months stay columns, not slabs.
                        BarMark(x: .value("Month", month.label), y: .value("Photos", month.value),
                                width: months.count < 12 ? .fixed(14) : .ratio(0.7))
                            .foregroundStyle(month.id == peak?.id ? MacTheme.accent : MacTheme.chartSoft)
                            .annotation(position: .top, spacing: 2) {
                                // Not on the last month: the total's label sits there.
                                if month.id == peak?.id, month.id != months.last?.id {
                                    Text(Int(month.value).formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
                                }
                            }
                    }
                    ForEach(Array(zip(months, totals)), id: \.0.id) { month, total in
                        LineMark(x: .value("Month", month.label), y: .value("Running total", total * scale))
                            .foregroundStyle(MacTheme.chartSeries[1])
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let last = months.last, let total = totals.last {
                        PointMark(x: .value("Month", last.label), y: .value("Running total", total * scale))
                            .foregroundStyle(MacTheme.chartSeries[1])
                            .symbolSize(30)
                            .annotation(position: .trailing, spacing: 4) {
                                Text(Int(total).formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: value.as(Double.self) == 0 ? [] : [3, 3]))
                            .foregroundStyle(MacTheme.separator)
                        AxisValueLabel().font(.caption2)
                    }
                    // The running total's own scale, on the right (board).
                    // Not at the top: the last point's own label says the total.
                    AxisMarks(position: .trailing, values: [0.25, 0.5, 0.75].map { top * $0 }) { value in
                        AxisValueLabel {
                            Text(Int(((value.as(Double.self) ?? 0) / scale).rounded()).formatted())
                                .font(.caption2).foregroundStyle(MacTheme.chartSeries[1])
                        }
                    }
                }
                .chartXAxis {
                    // A year's first month carries the year; the others no label.
                    AxisMarks { value in
                        if let key = value.as(String.self), key.hasSuffix("-01") || months.count == 1 {
                            AxisValueLabel { Text(MacCameraWords.yearLabel(key)).font(.caption2) }
                        }
                    }
                }
                .frame(height: 150)
                .accessibilityLabel(String(localized: "Photos per month and running total", comment: "Mac Statistics camera page: frames chart, VoiceOver"))
                HStack(spacing: 14) {
                    legend(MacTheme.chartSoft, String(localized: "Photos per month", comment: "Mac Statistics camera page legend"))
                    legend(MacTheme.chartSeries[1], String(localized: "Running total", comment: "Mac Statistics camera page legend"))
                }
                if let peak {
                    Text("Counts photos in your library, not the camera's shutter count. Busiest month: \(MacCameraWords.monthYear(peak.label, long: true)), \(String(AttributedString(localized: "^[\(Int(peak.value)) photo](inflect: true)", comment: "Mac Statistics camera page: photos of the busiest month").characters)).",
                         comment: "Mac Statistics camera page: what Frames in Library counts")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func lensCard(_ profile: StatisticsQueries.CameraProfile) -> some View {
        let known = model.lenses.filter { !$0.isUnknown }
        let top = known.map(\.value).max() ?? 1
        let shown = Int(known.map(\.value).reduce(0, +))
        let moreLenses = max(0, profile.lenses - known.count)
        let morePhotos = max(0, profile.photos - shown)
        return card(String(localized: "Lenses on This Body", comment: "Mac Statistics camera page card"), detail: StatsDateScope.allTime.title) {
            VStack(spacing: 6) {
                ForEach(Array(known.enumerated()), id: \.element.id) { index, lens in
                    let share = profile.photos > 0 ? lens.value / Double(profile.photos) : 0
                    Button {
                        var criteria = model.criteria
                        if let key = lens.drillKey { criteria.lenses = [key] }
                        open(criteria)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(lens.label).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(Int(lens.value).formatted()).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                Text(share.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 30, alignment: .trailing)
                            }
                            GeometryReader { geometry in
                                UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                                    .fill(index == 0 ? MacTheme.accent : MacTheme.chartSoft)
                                    .frame(width: max(4, geometry.size.width * lens.value / top))
                            }
                            .frame(height: 7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(AttributedString(localized: "Click to show ^[\(Int(lens.value)) photo](inflect: true)",
                                                  comment: "Mac Statistics: a column or row opens its photos").characters))
                    .accessibilityLabel("\(lens.label), \(Int(lens.value)) photos, \(share.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
            if morePhotos > 0 {
                Button { open(model.criteria) } label: {
                    HStack(spacing: 4) {
                Text(moreLenses > 0
                     ? String(AttributedString(localized: "^[\(moreLenses) more lens](inflect: true) · ^[\(morePhotos) photo](inflect: true)",
                                               comment: "Mac Statistics camera page: lenses not listed").characters)
                     : String(AttributedString(localized: "^[\(morePhotos) photo](inflect: true) without lens info",
                                               comment: "Mac Statistics camera page: photos with no lens").characters))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Show all of this camera's photos", comment: "Mac Statistics camera page: the lenses footer"))
            }
        }
    }

    /// The dashboard's column chart (tooltip, click → the photos), on this
    /// camera's photos.
    private func columnCard(_ title: String, detail: String, data: [ChartDatum], dimension: ChartDimension) -> some View {
        let known = data.filter { !$0.isUnknown }
        let spec = ChartSpec(title: title, kind: .bar, dimension: dimension)
        return card(title, detail: detail) {
            if known.isEmpty {
                Text("No photos with this info.", comment: "Mac Statistics camera page: an empty histogram")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                MacColumnChart(spec: spec, dimension: dimension, data: known) { criteria in
                    var criteria = criteria
                    criteria.cameraBodies = [model.model]
                    open(criteria)
                }
            }
        }
    }

    // MARK: Top Rated

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4))
    }

    private var topRated: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Top Rated", comment: "Mac Statistics camera page: the 5-star strip").font(.system(size: 15, weight: .semibold))
                Text(String(AttributedString(localized: "^[\(model.topRatedCount) photo](inflect: true) rated 5 stars",
                                             comment: "Mac Statistics camera page: how many 5-star photos").characters))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(String(localized: "Sort By", comment: "Mac Statistics camera page: Top Rated order"), selection: $model.topRatedSort) {
                    Text("Newest", comment: "Mac Statistics camera page: sort").tag(SortOption.dateTakenNewest)
                    Text("Oldest", comment: "Mac Statistics camera page: sort").tag(SortOption.dateTakenOldest)
                    Text("Highest ISO", comment: "Mac Statistics camera page: sort").tag(SortOption.isoDescending)
                    Text("Longest Lens", comment: "Mac Statistics camera page: sort").tag(SortOption.equivalentFocalLengthDescending)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("camera.sort")
                Button(String(localized: "Show All", comment: "Mac Statistics camera page: every 5-star photo in the Library")) {
                    open(model.topRatedCriteria)
                }
                .disabled(model.topRatedCount == 0)
                .accessibilityIdentifier("camera.showAll")
            }
            if model.topRatedFailed {
                HStack {
                    Text("Couldn't load the top-rated photos.", comment: "Mac Statistics camera page: top rated failed")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(String(localized: "Try Again", comment: "Mac Statistics: read again")) { model.retryTopRated() }
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
            } else if model.topRated.isEmpty {
                Text("No 5-star photos from this camera yet.", comment: "Mac Statistics camera page: no top rated")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 2) {
                    ForEach(model.topRated) { item in
                        Button { open(model.topRatedCriteria) } label: {
                        MacAssetCover(assetId: item.assetId, side: 300)
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            // Board: a dark fall at the foot behind the exposure line.
                            .overlay(alignment: .bottom) {
                                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 44)
                                    .allowsHitTesting(false)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Text(MacCameraWords.exposure(item))
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                    .padding(6)
                            }
                            .overlay(alignment: .top) {
                                HStack {
                                    if let format = MacCameraWords.format(item) { badge(format) }
                                    Spacer(minLength: 2)
                                    badge("★★★★★")
                                }
                                .padding(6)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help(String(localized: "Show the 5-star photos in the Library", comment: "Mac Statistics camera page: a Top Rated tile"))
                        .accessibilityLabel(item.originalFilename ?? "")
                    }
                    // A short row keeps its tiles square, not stretched.
                    ForEach(model.topRated.count..<8, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }
}

enum MacCameraWords {
    /// "Canon · Full Frame sensor (1.0× crop) · first photo January 14, 2023 · latest October 1, 2026".
    static func subtitle(_ profile: StatisticsQueries.CameraProfile) -> String {
        var parts: [String] = []
        if let brand = profile.brand { parts.append(brand) }
        if let format = profile.sensorFormat {
            if let crop = profile.cropFactor {
                parts.append(String(localized: "\(format.displayName) sensor (\(crop.formatted(.number.precision(.fractionLength(1))))× crop)",
                                    comment: "Mac Statistics camera page: sensor and crop factor"))
            } else {
                parts.append(String(localized: "\(format.displayName) sensor", comment: "Mac Statistics camera page: sensor"))
            }
        }
        if let first = profile.firstPhoto {
            parts.append(String(localized: "first photo \(first.formatted(date: .long, time: .omitted))", comment: "Mac Statistics camera page"))
        }
        if let latest = profile.latestPhoto {
            parts.append(String(localized: "latest \(latest.formatted(date: .long, time: .omitted))", comment: "Mac Statistics camera page"))
        }
        return parts.joined(separator: " · ")
    }

    /// "2026-08" → "Aug 2026", "August 2026", or "Aug 26".
    static func monthYear(_ key: String, long: Bool = false, short: Bool = false) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else { return key }
        if short { return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) }
        return date.formatted(.dateTime.month(long ? .wide : .abbreviated).year())
    }

    /// The format badge of a tile: RAW, HEIC, JPG…
    static func format(_ item: LibraryGridItem) -> String? {
        guard let name = item.originalFilename, let ext = name.split(separator: ".").last.map({ $0.uppercased() }) else { return nil }
        return ["CR3", "CR2", "ARW", "NEF", "RAF", "DNG", "ORF", "RW2"].contains(ext) ? "RAW" : (ext == "JPEG" ? "JPG" : ext)
    }

    /// "2024-01" → "2024".
    static func yearLabel(_ key: String) -> String { String(key.prefix(4)) }

    static func exposure(_ item: LibraryGridItem) -> String {
        var parts: [String] = []
        if let iso = item.iso { parts.append("ISO \(iso)") }
        if let focal = item.equivalentFocalLength ?? item.focalLength { parts.append("\(Int(focal.rounded()))mm") }
        if let aperture = item.aperture { parts.append(MetadataFormatter.aperture(aperture) ?? "") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
