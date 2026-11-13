import Foundation
import GRDB

/// "One of these tables changed" as an async sequence, for a screen that
/// re-runs its own query when the data under it moves — a smart album's
/// grid and the Collections tiles (FS-06.08 §3c A1). Carries no rows: the
/// screen decides when to read again. Buffers one pending signal, so a burst
/// of writes is one wake-up, not one per commit.
enum DatabaseChangeSignal {
    static func changes(in database: AppDatabase, tables: [String]) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observation = DatabaseRegionObservation(tracking: tables.map { Table($0) })
            let cancellable = observation.start(
                in: database.writer,
                onError: { _ in continuation.finish() },
                onChange: { _ in continuation.yield() }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
