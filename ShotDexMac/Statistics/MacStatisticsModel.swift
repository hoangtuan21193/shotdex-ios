import Foundation

/// The Mac's Statistics dashboard (board `MAC_Statistics`, FS-18.04 §2):
/// its charts, each one's data within its own range, the Insights card and
/// the Source popup. Every query and every write runs off the main actor;
/// the screen only reads what lands here.
@MainActor
@Observable
final class MacStatisticsModel {
    enum InsightsLoad: Equatable {
        case loading
        case loaded(InsightsCardState)
        case failed
    }

    /// Where the Mac remembers it planted its own dashboard: a board the
    /// user cleared stays cleared.
    static let seededKey = "stats.mac.didSeedCharts"

    private(set) var charts: [ChartSpec] = []
    /// A chart's data once read; absent while it loads.
    private(set) var results: [String: [ChartDatum]] = [:]
    /// Charts whose query failed: "Couldn't load this chart." rather than
    /// "No photos in this range."
    private(set) var failedCharts: Set<String> = []
    /// A pass is reading (a Source change): the board dims until it lands.
    private(set) var isReloading = false
    /// Photos in each chart's range, for the shares and "N photos without
    /// this info." — keyed by chart id.
    private(set) var scopeTotals: [String: Int] = [:]
    private(set) var totalPhotos = 0
    private(set) var totalVideos = 0
    private(set) var hasLoaded = false
    /// The chart list could not be read: the screen says so, with Try Again.
    private(set) var failedToLoad = false
    private(set) var insights: InsightsLoad = .loading

    /// The Source popup: a passing filter of the screen, never written into
    /// a chart. Nil is All Sources.
    var sourceId: String? {
        didSet {
            guard sourceId != oldValue else { return }
            // The last source's sentences must not stand under the new one.
            insights = .loading
            reload()
        }
    }

    /// A source removed from the sidebar: the popup goes back to All Sources
    /// rather than counting a source that is not there.
    func keep(sourceIds: Set<String>) {
        if let sourceId, !sourceIds.contains(sourceId) { self.sourceId = nil } else { reload() }
    }

    private let database: AppDatabase
    private let chartStore: ChartStore
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Writes go one after another, in the order made.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        chartStore = ChartStore(database: database)
    }

    private var queries: StatisticsQueries {
        var queries = StatisticsQueries(database: database)
        queries.sourceId = sourceId
        return queries
    }

    // MARK: Loading

    /// The chart list (planting the Mac's set once) and every chart's data,
    /// then Insights on their own — the charts never wait for them.
    func reload() {
        generation += 1
        let generation = self.generation
        isReloading = true
        let queries = self.queries
        let chartStore = self.chartStore
        var seeded = UserDefaults.standard.bool(forKey: Self.seededKey)
        #if DEBUG
        // The demo library is a new database each launch: it gets the board again.
        if MacDemoLibrary.isOn { seeded = false }
        #endif
        task?.cancel()
        let previousWrite = writeTask
        task = Task.detached(priority: .userInitiated) { [weak self] in
            // A pending write lands first: the read sees it.
            await previousWrite?.value
            let loaded = try? chartStore.loadCharts(seededGeneration: seeded ? ChartStore.currentSeedGeneration : 0,
                                                     defaults: ChartSpec.macDefaultSpecs())
            let charts = loaded?.charts.map(\.spec) ?? []
            var results: [String: [ChartDatum]] = [:]
            var failed: Set<String> = []
            var totals: [String: Int] = [:]
            var totalByScope: [StatsDateScope: Int] = [:]
            for spec in charts {
                if Task.isCancelled { return }
                if let data = try? queries.chartData(for: spec, scope: spec.scope) {
                    results[spec.id] = data
                } else {
                    failed.insert(spec.id)
                }
                if let known = totalByScope[spec.scope] {
                    totals[spec.id] = known
                } else {
                    let total = (try? queries.totalPhotos(scope: spec.scope)) ?? 0
                    totalByScope[spec.scope] = total
                    totals[spec.id] = total
                }
            }
            let total = (try? queries.totalPhotos(scope: .allTime)) ?? 0
            let videos = (try? queries.totalVideos(scope: .allTime)) ?? 0
            await self?.apply(charts: charts, results: results, failed: failed, totals: totals, total: total, videos: videos,
                              loaded: loaded != nil, generation: generation)
            if Task.isCancelled { return }
            let insights: InsightsLoad
            do {
                let inputs = try queries.insightInputs()
                insights = .loaded(InsightSelector.cardState(indexedRows: total, inputs: inputs))
            } catch {
                insights = .failed
            }
            await self?.applyInsights(insights, generation: generation)
        }
    }

    private func apply(charts: [ChartSpec], results: [String: [ChartDatum]], failed: Set<String>, totals: [String: Int],
                       total: Int, videos: Int, loaded: Bool, generation: Int) {
        // A Source picked, or a chart changed, while this pass ran: only the newest lands.
        guard generation == self.generation else { return }
        isReloading = false
        failedToLoad = !loaded
        self.charts = charts
        self.results = results
        failedCharts = failed
        scopeTotals = totals
        totalPhotos = total
        totalVideos = videos
        hasLoaded = true
        if loaded { UserDefaults.standard.set(true, forKey: Self.seededKey) }
    }

    private func applyInsights(_ load: InsightsLoad, generation: Int) {
        guard generation == self.generation else { return }
        insights = load
    }

    // MARK: Editing

    /// The cards of the top row and the cards below, in order.
    var kpis: [ChartSpec] { charts.filter { $0.kind == .kpi } }
    var cards: [ChartSpec] { charts.filter { $0.kind != .kpi } }

    /// Adds a chart at the end, with a fresh id: the same offer added twice
    /// is two charts.
    @discardableResult
    func add(_ offer: ChartSpec) -> String {
        var spec = ChartSpec(title: offer.title, kind: offer.kind, dimension: offer.dimension, metric: offer.metric,
                             filter: offer.filter, seriesSplit: offer.seriesSplit, topN: offer.topN, scope: offer.scope)
        spec.drawsColumns = offer.drawsColumns
        let position = charts.count
        charts.append(spec)
        write { store in try store.upsert(StatChart(spec: spec, position: position)) }
        loadOne(spec)
        return spec.id
    }

    /// One chart's data, merged in: adding a chart does not read the other fifteen.
    private func loadOne(_ spec: ChartSpec) {
        let queries = self.queries
        let source = sourceId
        Task.detached(priority: .userInitiated) { [weak self] in
            let data = try? queries.chartData(for: spec, scope: spec.scope)
            let total = (try? queries.totalPhotos(scope: spec.scope)) ?? 0
            await self?.merge(spec, data: data, total: total, source: source)
        }
    }

    private func merge(_ spec: ChartSpec, data: [ChartDatum]?, total: Int, source: String?) {
        let id = spec.id
        // A Source picked meanwhile, or the chart edited again: this read is stale.
        guard source == sourceId, charts.first(where: { $0.id == id }) == spec else { return }
        if let data { results[id] = data; failedCharts.remove(id) } else { failedCharts.insert(id) }
        scopeTotals[id] = total
    }

    /// The Mac's own cards that are not on the board, back at the end.
    func restoreDefaults() {
        for spec in addable.filter({ offer in ChartSpec.macDefaultSpecs().contains { $0.title == offer.title } }) {
            add(spec)
        }
    }

    /// The editor's Save on a chart that exists: same place, new data.
    func update(_ spec: ChartSpec) {
        guard let index = charts.firstIndex(where: { $0.id == spec.id }) else { add(spec); return }
        // The old figures stay until the new ones land: no blank flash on a rename.
        charts[index] = spec
        failedCharts.remove(spec.id)
        write { store in try store.upsert(StatChart(spec: spec, position: index)) }
        loadOne(spec)
    }

    /// A copy right after the original, "Copy" on its title.
    func duplicate(_ id: String) {
        guard let index = charts.firstIndex(where: { $0.id == id }) else { return }
        let original = charts[index]
        var copy = original
        copy.id = UUID().uuidString
        copy.title = String(localized: "\(original.title) Copy", comment: "Mac Statistics: a duplicated chart's title")
        charts.insert(copy, at: index + 1)
        results[copy.id] = results[id]
        scopeTotals[copy.id] = scopeTotals[id]
        let ordered = charts.map(\.id)
        write { store in
            try store.upsert(StatChart(spec: copy, position: index + 1))
            try store.updatePositions(ordered)
        }
    }

    func delete(_ id: String) {
        charts.removeAll { $0.id == id }
        results[id] = nil
        let ordered = charts.map(\.id)
        write { store in
            try store.delete(id: id)
            try store.updatePositions(ordered)
        }
    }

    /// Move Earlier / Move Later: past the next chart of the same row — a
    /// number among the numbers, a card among the cards.
    func move(_ id: String, earlier: Bool) {
        guard let index = charts.firstIndex(where: { $0.id == id }) else { return }
        let isKPI = charts[index].kind == .kpi
        let others = earlier ? Array(charts.indices.filter { $0 < index }.reversed()) : charts.indices.filter { $0 > index }
        guard let target = others.first(where: { (charts[$0].kind == .kpi) == isKPI }) else { return }
        charts.swapAt(index, target)
        let ordered = charts.map(\.id)
        write { store in try store.updatePositions(ordered) }
    }

    func canMove(_ id: String, earlier: Bool) -> Bool {
        guard let index = charts.firstIndex(where: { $0.id == id }) else { return false }
        let isKPI = charts[index].kind == .kpi
        let range = earlier ? Array(charts[..<index]) : Array(charts[(index + 1)...])
        return range.contains { ($0.kind == .kpi) == isKPI }
    }

    /// A store write off the main actor, after the writes before it. A pass
    /// already reading is dropped (it read the board before this change);
    /// a chart with no data yet, or a write that failed, reads again.
    private func write(_ body: @escaping @Sendable (ChartStore) throws -> Void) {
        let store = chartStore
        let previous = writeTask
        generation += 1
        // Only a pass this write drops reads again (a chart just added loads on its own).
        let needsData = isReloading
        writeTask = Task.detached(priority: .userInitiated) { [weak self] in
            await previous?.value
            let failed = (try? body(store)) == nil
            if failed || needsData { await self?.reload() }
        }
    }

    // MARK: Add Chart

    /// What Add Chart offers (until the chart editor, row 30): the Mac's own
    /// cards not on the board, then one bar chart per dimension a bar takes.
    var addable: [ChartSpec] {
        let titles = Set(charts.map(\.title))
        let missing = ChartSpec.macDefaultSpecs().filter { !titles.contains($0.title) }
        let bars = ChartKind.bar.allowedDimensions
            .filter { dimension in !charts.contains { $0.kind == .bar && $0.dimension == dimension && $0.metric == .photoCount } }
            .filter { dimension in !missing.contains { $0.dimension == dimension } }
            .map { ChartSpec(title: $0.displayName, kind: .bar, dimension: $0, topN: 5) }
        return missing + bars
    }
}
