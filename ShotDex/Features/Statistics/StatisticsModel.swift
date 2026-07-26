import Foundation

/// Owns the Statistics dashboard: the user's chart specs, their computed
/// data (each chart scoped by its own date range), and the edit operations
/// that persist changes. All aggregate queries run off the main thread.
@MainActor
@Observable
final class StatisticsModel {
    private let statisticsQueries: StatisticsQueries
    private let chartStore: ChartStore

    /// The dashboard's charts, in display order.
    private(set) var charts: [ChartSpec] = []
    /// Computed points per chart id (empty until first load completes).
    private(set) var results: [String: [ChartDatum]] = [:]
    /// Total indexed items (all time) — drives the "no indexed photos" empty
    /// state; the dashboard has no global scope, so this is unscoped.
    private(set) var totalPhotos = 0
    /// Oldest capture date in the index — bounds each chart's custom range picker.
    private(set) var earliestDate: Date?
    private(set) var isLoading = false
    /// True once the initial load (charts + data) has finished at least once.
    private(set) var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.statisticsQueries = dependencies.statisticsQueries
        self.chartStore = dependencies.chartStore
    }

    /// Loads the chart list (seeding defaults on first ever run) and then every
    /// chart's data, each within its own scope.
    func load() {
        reload(reloadCharts: true)
    }

    private func reload(reloadCharts: Bool) {
        isLoading = true
        let statisticsQueries = self.statisticsQueries
        let chartStore = self.chartStore
        let knownCharts = self.charts
        let seeded = UserDefaults.standard.bool(forKey: SettingsKeys.didSeedStatCharts)

        Task.detached(priority: .userInitiated) { [weak self] in
            // Resolve the spec list.
            var didSeed = false
            let charts: [ChartSpec]
            if reloadCharts {
                if seeded {
                    charts = ((try? chartStore.fetchAllOrdered()) ?? []).map(\.spec)
                } else {
                    // First run: seed the defaults, remember we did so.
                    charts = ((try? chartStore.seedDefaultsIfEmpty()) ?? []).map(\.spec)
                    didSeed = true
                }
            } else {
                charts = knownCharts
            }

            // Aggregate every chart within its own scope.
            var results: [String: [ChartDatum]] = [:]
            for spec in charts {
                results[spec.id] = (try? statisticsQueries.chartData(for: spec, scope: spec.scope)) ?? []
            }
            let total = (try? statisticsQueries.totalPhotos(scope: .allTime)) ?? 0
            let earliest = try? statisticsQueries.earliestCreationDate()

            await self?.apply(
                charts: charts, results: results, total: total,
                earliest: earliest, didSeed: didSeed
            )
        }
    }

    private func apply(
        charts: [ChartSpec],
        results: [String: [ChartDatum]],
        total: Int,
        earliest: Date?,
        didSeed: Bool
    ) {
        self.charts = charts
        self.results = results
        self.totalPhotos = total
        self.earliestDate = earliest
        if didSeed { UserDefaults.standard.set(true, forKey: SettingsKeys.didSeedStatCharts) }
        self.isLoading = false
        self.hasLoaded = true
    }

    // MARK: Editing

    /// Appends a new chart at the end and reloads its data.
    func addChart(_ spec: ChartSpec) {
        try? chartStore.upsert(StatChart(spec: spec, position: charts.count))
        reload(reloadCharts: true)
    }

    /// Replaces an existing chart in place (keeping its position) and reloads.
    func updateChart(_ spec: ChartSpec) {
        let position = charts.firstIndex { $0.id == spec.id } ?? charts.count
        try? chartStore.upsert(StatChart(spec: spec, position: position))
        reload(reloadCharts: true)
    }

    func deleteChart(id: String) {
        try? chartStore.delete(id: id)
        results[id] = nil
        charts.removeAll { $0.id == id }
        try? chartStore.updatePositions(charts.map(\.id))
    }

    func deleteCharts(at offsets: IndexSet) {
        let ids = offsets.map { charts[$0].id }
        for id in ids { try? chartStore.delete(id: id) }
        charts.remove(atOffsets: offsets)
        for id in ids { results[id] = nil }
        try? chartStore.updatePositions(charts.map(\.id))
    }

    /// Reorders charts in place and persists the new positions.
    func moveCharts(from offsets: IndexSet, to destination: Int) {
        charts.move(fromOffsets: offsets, toOffset: destination)
        try? chartStore.updatePositions(charts.map(\.id))
    }
}
