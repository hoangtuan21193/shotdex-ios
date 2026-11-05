import Foundation

/// What a common-photos run did, in words (FS-19.08 §7): the log window's
/// rows, the CSV left in the destination, and the history the server's
/// changes owe the app.
enum CommonPhotosLog {
    static func status(_ status: CommonPhotosItem.Status) -> String {
        switch status {
        case .pending: String(localized: "Waiting", comment: "Common photos log: a photo not reached yet")
        case .copying: String(localized: "Copying…", comment: "Common photos log: a photo being copied")
        case .moving, .placed: String(localized: "Moving…", comment: "Common photos log: a photo being moved")
        case .copied: String(localized: "Copied", comment: "Common photos log status")
        case .moved: String(localized: "Moved", comment: "Common photos log status")
        case .skipped: String(localized: "Skipped", comment: "Common photos log status")
        case .failed: String(localized: "Failed", comment: "Common photos log status")
        case .undone: String(localized: "Undone", comment: "Common photos log status: the photo was taken back by an undo")
        }
    }

    /// The log window's Check cell (FS-19.08 §6e).
    static func check(_ method: CommonPhotosItem.CheckMethod?) -> String {
        switch method {
        case .quick: String(localized: "Quick", comment: "Common photos log, Check column: Same by three samples")
        case .full: String(localized: "Full", comment: "Common photos log, Check column: Same by every byte")
        case nil: ""
        }
    }

    /// The log window's File info cell (FS-19.08 §6e).
    static func fileInfo(_ outcome: FileInfoOutcome?) -> String {
        switch outcome {
        case .kept: String(localized: "Kept", comment: "Common photos log, File info column: the copy has its source's dates and flags")
        case .datesNotKept: String(localized: "Dates not kept", comment: "Common photos log, File info column: the server gave the copy today's date")
        case .tagsNotKept: String(localized: "Tags not kept", comment: "Common photos log, File info column: dates kept, Finder tags lost")
        case nil: "—"
        }
    }

    static func reason(_ item: CommonPhotosItem) -> String {
        guard let (code, detail) = item.failure else { return "" }
        switch code {
        case .alreadyThere: return String(localized: "already there", comment: "Common photos log reason: the same bytes were in the destination")
        case .changedOnServer: return String(localized: "changed on server", comment: "Common photos log reason: a copy changed since the scan")
        case .checksumMismatch: return String(localized: "checksum mismatch", comment: "Common photos log reason: the copy read back did not match")
        case .noSource: return String(localized: "no source", comment: "Common photos log reason: the record lists no source file")
        case .unreadableRecord: return String(localized: "record could not be read", comment: "Common photos log reason")
        case .sidecarNotCopied: return String(localized: "sidecar not copied", comment: "Common photos log reason: the .xmp beside the photo was not copied")
        case .noOtherCopy: return String(localized: "no other copy", comment: "Common photos undo reason: no source copy is left, so the shared copy stays")
        case .changedInShared: return String(localized: "changed in Shared", comment: "Common photos undo reason: the copy in the shared folder was edited since")
        case .nameTaken:
            let path = detail.map { " (\($0))" } ?? ""
            return String(localized: "name taken\(path)", comment: "Common photos undo reason: the old path now holds other bytes; the path follows in brackets")
        case .serverError: return detail ?? String(localized: "server error", comment: "Common photos log reason")
        case .liveStillFailed: return String(localized: "Live Photo still not moved", comment: "Common photos log reason: the motion of a Live Photo stays because its still did not move")
        case .liveMotionChanged: return String(localized: "Live Photo video changed on server", comment: "Common photos log reason: the still of a Live Photo stays because its video changed since the scan")
        }
    }

    /// The CSV left in the destination (FS-19.08 §6, AC-129): one row per
    /// photo — Status, Name, From (every source, `; `-separated), To,
    /// SHA-256, Reason. Fixed English words, whatever the Mac's language, so
    /// a script or another Mac reads it the same; a UTF-8 BOM so Excel shows
    /// `Tuấn` as written; names from the server that would read as a formula
    /// (`=`, `+`, `-`, `@`) start with `'`.
    /// An undo's CSV (`isUndo`) has the same columns; its rows read
    /// Undone or Not undone (§6b). `File info` (§6e) says whether the copy
    /// kept its source's dates: `kept`, `dates not kept`, `tags not kept`,
    /// empty where the run wrote no copy; last, so a script reading the
    /// earlier columns by position still reads them.
    static func csv(_ items: [CommonPhotosItem], isUndo: Bool = false) -> String {
        var lines = [CSVField.line(["Status", "Name", "From", "To", "SHA-256", "Reason", "File info", "Check"])]
        for item in items {
            lines.append(CSVField.line([
                isUndo ? (item.status == .undone ? "Undone" : item.isDone ? "Not undone" : csvStatus(item.status)) : csvStatus(item.status),
                item.sources.first.map { ServerUploadPath.lastComponent(of: $0.path) } ?? "",
                item.sources.map(\.path).joined(separator: "; "),
                item.destinationPath ?? "",
                // A Quick Check photo not read yet has no SHA-256 (§6e).
                item.sha256.hasPrefix(CommonPhoto.quickPrefix) ? "" : item.sha256,
                csvReason(item),
                // An undo's row has its own verdict: a Move's copies put
                // back with their dates or not; a Copy's undo dates nothing.
                item.fileInfo?.rawValue ?? "",
                // How Same was proven (§6e): quick or full; blank on an undo's rows.
                isUndo || item.status == .skipped ? "" : item.checkMethod?.rawValue ?? "",
            ].map(defused)))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvStatus(_ status: CommonPhotosItem.Status) -> String {
        switch status {
        case .pending: "Waiting"
        case .copying, .moving, .placed: "Unfinished"
        case .copied: "Copied"
        case .moved: "Moved"
        case .skipped: "Skipped"
        case .failed: "Failed"
        case .undone: "Undone"
        }
    }

    static func csvReason(_ item: CommonPhotosItem) -> String {
        guard let (code, detail) = item.failure else { return "" }
        switch code {
        case .alreadyThere: return "already there"
        case .changedOnServer: return "changed on server"
        case .checksumMismatch: return "checksum mismatch"
        case .noSource: return "no source"
        case .unreadableRecord: return "record could not be read"
        case .sidecarNotCopied: return "sidecar not copied"
        case .noOtherCopy: return "no other copy"
        case .changedInShared: return "changed in Shared"
        case .nameTaken: return detail.map { "name taken: \($0)" } ?? "name taken"
        case .liveStillFailed: return "Live Photo still not moved"
        case .liveMotionChanged: return "Live Photo video changed on server"
        case .serverError: return detail.map { "server error: \($0)" } ?? "server error"
        }
    }

    /// A field a spreadsheet would run as a formula, made text.
    private static func defused(_ field: String) -> String {
        guard let first = field.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return field }
        return "'" + field
    }

    /// `ShotDex Common Photos 2026-11-02 1430 Undo.csv`.
    static func undoCSVName(at date: Date, timeZone: TimeZone = .current) -> String {
        (csvName(at: date, timeZone: timeZone) as NSString).deletingPathExtension + " Undo.csv"
    }

    /// `ShotDex Common Photos 2026-11-02 1430.csv`, in this Mac's time.
    /// A Keep-gathering day's log (FS-19.08 §6c), written again after every
    /// pass of the day: `ShotDex Common Photos 2026-11-03 auto.csv`.
    static func dayCSVName(_ day: String) -> String {
        "ShotDex Common Photos \(day) auto.csv"
    }

    static func csvName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "ShotDex Common Photos \(formatter.string(from: date)).csv"
    }

    /// What the upload, download and backup history must follow (FS-17.01
    /// §4b): every source this run removed or renamed now has its bytes at
    /// the destination, so its proof moves there rather than going.
    struct HistoryChange: Equatable, Sendable {
        let from: String
        let to: String
    }

    static func historyChanges(_ items: [CommonPhotosItem]) -> [HistoryChange] {
        items.flatMap { item -> [HistoryChange] in
            guard item.status == .moved || item.status == .failed, let destination = item.destinationPath else { return [] }
            return item.sources.filter(\.isRemoved).map { HistoryChange(from: $0.path, to: destination) }
        }
    }
}
