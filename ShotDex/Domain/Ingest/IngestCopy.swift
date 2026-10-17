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
        guard count >= 1_000_000_000 else { return count.formatted(.byteCount(style: .file, spellsOutZero: false)) }
        let gigabytes = (Double(count) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(gigabytes) GB", table: table, comment: "A size in gigabytes, one decimal")
    }

    // MARK: Screen

    /// The card header: `812 new photos · 234 already imported · skipped`.
    static func header(new: Int, imported: Int) -> String {
        let newPart = String(localized: "\(new) new photos", table: table, comment: "Import from Card header: photos not imported yet")
        guard imported > 0 else { return newPart }
        return newPart + " · " + String(localized: "\(imported) already imported · skipped", table: table,
                                         comment: "Import from Card header: photos the history says are imported")
    }

    static func checkedLine(count: Int, bytes: Int64) -> String {
        String(localized: "\(count) checked · \(Self.bytes(bytes))", table: table, comment: "Import from Card: ticked photos and their size")
    }

    static func importButton(count: Int) -> String {
        String(localized: "Import \(count) Photos", table: table, comment: "Import from Card: the import button")
    }

    static func everythingImported(card: String) -> String {
        String(localized: "Everything on \(card) is already imported.", table: table, comment: "Import from Card: New is empty")
    }

    static func collapsedDay(_ count: Int) -> String {
        String(localized: "\(count) already imported", table: table, comment: "Import from Card: a day whose photos are all imported, collapsed")
    }

    static func newOnDay(_ count: Int) -> String {
        String(localized: "\(count) new", table: table, comment: "Import from Card: new photos on a day")
    }

    /// `Imported 811 photos. You can remove EOS_DIGITAL now.` — iOS lets an
    /// app eject a camera but not a card in Files (plan Q3).
    static func finishedBanner(count: Int, card: String, ejected: Bool, canRemove: Bool) -> String {
        let imported = String(localized: "Imported \(count) photos.", table: table, comment: "Card import finished banner")
        if ejected {
            return imported + " " + String(localized: "\(card) ejected.", table: table, comment: "Card import banner: the card was let go")
        }
        if canRemove {
            return imported + " " + String(localized: "You can remove \(card) now.", table: table,
                                           comment: "Card import banner: every copy verified, the card can be taken out")
        }
        return imported
    }

    static func usedOf(used: Int64, total: Int64) -> String {
        String(localized: "\(bytes(used)) of \(bytes(total)) used", table: table, comment: "Import from Card header: card space")
    }

    // MARK: Options

    /// `Year / Date`, or the pattern as typed.
    static func foldersSummary(_ folders: IngestFolderTemplate) -> String {
        let words = folders.pattern
            .replacingOccurrences(of: "{year}", with: String(localized: "Year", table: table, comment: "Import folders token"))
            .replacingOccurrences(of: "{date}", with: String(localized: "Date", table: table, comment: "Import folders token"))
        return words.isEmpty ? String(localized: "None", table: table, comment: "Import folders: everything in the destination itself") : words.replacingOccurrences(of: "/", with: " / ")
    }

    static func nameTitle(_ template: FileNameTemplate) -> String {
        template == IngestSettings.dateAndNumber
            ? String(localized: "Date and Number", table: table, comment: "Import file name preset: {date}_{originalNumber}")
            : ExportCopy.templateTitle(template)
    }

    /// `Linh Pham · 2 keywords`.
    static func metadataSummary(_ preset: IngestMetadataPreset) -> String {
        var parts: [String] = []
        if !preset.creator.isEmpty { parts.append(preset.creator) }
        if !preset.keywords.isEmpty {
            parts.append(String(localized: "\(preset.keywords.count) keywords", table: table, comment: "Import metadata summary: keyword count"))
        }
        return parts.isEmpty ? String(localized: "None", table: table, comment: "Import metadata: nothing set") : parts.joined(separator: " · ")
    }

    /// `811 photos · 24.6 GB to T7 RAW Archive`.
    static func summaryFooter(count: Int, bytes: Int64, destination: String) -> String {
        String(localized: "\(count) photos · \(Self.bytes(bytes)) to \(destination)", table: table,
               comment: "Import from Card footer: what Import will copy and where")
    }

    /// `412 of 811 · 12.3 of 24.6 GB`.
    static func progressLine(_ progress: IngestProgress) -> String {
        String(localized: "\(progress.done) of \(progress.total) · \(bytes(progress.bytesDone)) of \(bytes(progress.bytesTotal))", table: table,
               comment: "Card import progress: photos and bytes done of the batch")
    }
}
