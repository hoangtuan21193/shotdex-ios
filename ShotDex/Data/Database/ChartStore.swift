import Foundation
import GRDB

/// Reads and writes the Statistics dashboard's chart specs (`stat_charts`).
struct ChartStore: Sendable {
    let database: AppDatabase

    /// All charts in display order.
    func fetchAllOrdered() throws -> [StatChart] {
        try database.reader.read { db in
            try StatChart.order(Column("position")).fetchAll(db)
        }
    }

    /// Inserts or updates a chart (keyed by spec id).
    func upsert(_ chart: StatChart) throws {
        try database.writer.write { db in
            try chart.upsert(db)
        }
    }

    func delete(id: String) throws {
        _ = try database.writer.write { db in
            try StatChart.deleteOne(db, key: id)
        }
    }

    /// Rewrites `position` to match the given id order (0-based).
    func updatePositions(_ orderedIds: [String]) throws {
        try database.writer.write { db in
            for (index, id) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE stat_charts SET position = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    /// The newest seed generation: the six charts of `ChartSpec.defaultSpecs()`.
    /// Generation 1 planted only the first two of them.
    static let currentSeedGeneration = 2

    /// The dashboard's charts, seeding what this install has not had yet.
    /// `seededGeneration` is what the install already went through: 0 never
    /// seeded (a fresh install → all six), 1 the old two (→ append the four
    /// it is missing at the end, after whatever the user has now), 2 nothing
    /// to do — a board the user cleared stays empty. Returns the charts in
    /// order and the generation to remember.
    func loadCharts(seededGeneration: Int) throws -> (charts: [StatChart], seededGeneration: Int) {
        try database.writer.write { db in
            let defaults = ChartSpec.defaultSpecs()
            switch seededGeneration {
            case ..<1:
                if try StatChart.fetchCount(db) == 0 {
                    for (index, spec) in defaults.enumerated() {
                        try StatChart(spec: spec, position: index).insert(db)
                    }
                }
            case 1:
                let start = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM stat_charts") ?? -1) + 1
                for (offset, spec) in defaults.dropFirst(ChartSpec.firstSeedGenerationCount).enumerated() {
                    try StatChart(spec: spec, position: start + offset).insert(db)
                }
            default:
                break
            }
            let charts = try StatChart.order(Column("position")).fetchAll(db)
            return (charts, max(seededGeneration, Self.currentSeedGeneration))
        }
    }

    /// Seeds the default dashboard when the table is empty, then returns the
    /// stored charts in order — `loadCharts(seededGeneration: 0)`.
    @discardableResult
    func seedDefaultsIfEmpty() throws -> [StatChart] {
        try loadCharts(seededGeneration: 0).charts
    }
}
