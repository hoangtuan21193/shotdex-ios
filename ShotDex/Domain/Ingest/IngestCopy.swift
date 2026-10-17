import Foundation

/// Every sentence of a card import (FS-20 §5–8), in the `Ingest` table.
enum IngestCopy {
    static let table = "Ingest"

    /// The line under a run that did not finish (FS-20 §8).
    static func endingMessage(_ summary: IngestSummary, card: String, destination: String) -> String? {
        let done = summary.imported.count
        let total = summary.total
        switch summary.ending {
        case .finished:
            return nil
        case .stopped:
            return String(localized: "Import stopped — \(done) of \(total) imported.", table: table,
                          comment: "Card import stopped by the user; photos imported of the batch")
        case .cardDisconnected:
            return String(localized: "\(card) was disconnected. \(done) of \(total) imported.", table: table,
                          comment: "Card import: the card was pulled out mid-batch; card name, then imported of total")
        case .destinationFailed(.full):
            return String(localized: "“\(destination)” is full — \(done) of \(total) imported.", table: table,
                          comment: "Card import: the destination filled up mid-batch")
        case .destinationFailed(.permissionDenied):
            return String(localized: "ShotDex can't write to “\(destination)” — \(done) of \(total) imported.", table: table,
                          comment: "Card import: the destination refused writes")
        case .destinationFailed:
            return String(localized: "“\(destination)” was disconnected. \(done) of \(total) imported.", table: table,
                          comment: "Card import: the destination drive went away mid-batch")
        }
    }

    /// The backup's line in the summary, when it did not finish.
    static func backupLine(_ summary: IngestSummary) -> String? {
        guard summary.backupIncomplete else { return nil }
        return String(localized: "Backup incomplete — \(summary.backedUp.count) of \(summary.imported.count).", table: table,
                      comment: "Card import summary: the backup drive went away; backed up of imported")
    }

    /// The line under a file that failed.
    static func failedLine(_ failure: IngestFailure) -> String {
        switch failure {
        case .checksumMismatch:
            String(localized: "The copy didn't match the card. Nothing was imported for this photo.", table: table,
                   comment: "Card import summary: a file read back differently from the card, twice")
        case .unreadable, .cardDisconnected, .destination:
            String(localized: "Couldn't read this file from the card.", table: table,
                   comment: "Card import summary: one file could not be read")
        }
    }

    /// `24.6 GB`, `12.0 GB` — one decimal from a gigabyte up, so two sizes
    /// side by side read alike (FS-20 §6); below, as Files writes them.
    static func bytes(_ count: Int64) -> String {
        guard count >= 1_000_000_000 else { return count.formatted(.byteCount(style: .file)) }
        let gigabytes = (Double(count) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(gigabytes) GB", table: table, comment: "A size in gigabytes, one decimal")
    }
}
