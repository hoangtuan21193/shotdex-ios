import Foundation
import GRDB

/// Reads and writes the Statistics dashboard's chart specs (`stat_charts`).
struct StatChartDAO: Sendable {
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

    /// Seeds the default dashboard when the table is empty, then returns the
    /// stored charts in order. Callers gate the *first-run* decision with a
    /// persisted flag (see `StatisticsModel`) so a board a user deliberately
    /// cleared isn't re-seeded; the empty-check here is just a double-insert
    /// guard.
    @discardableResult
    func seedDefaultsIfEmpty() throws -> [StatChart] {
        try database.writer.write { db in
            if try StatChart.fetchCount(db) == 0 {
                for (index, spec) in ChartSpec.defaultSpecs().enumerated() {
                    try StatChart(spec: spec, position: index).insert(db)
                }
            }
            return try StatChart.order(Column("position")).fetchAll(db)
        }
    }
}
