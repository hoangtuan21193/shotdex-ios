import Foundation
import GRDB

/// One shared photo of a common-photos run and what happened to it (FS-19.08
/// §6–7). The runner writes it before every server step and after, so a
/// resume reads from here alone where each photo stands.
struct CommonPhotosItem: Hashable, Sendable {
    enum Status: String, Sendable {
        case pending
        /// Copy: the part file is being written (`partPath`) toward
        /// `destinationPath`.
        case copying
        /// Move: `movedFrom` is being renamed to `destinationPath`.
        case moving
        /// The destination copy is in place and checked; for a Move, the
        /// other sources are not all removed yet.
        case placed
        case copied, moved, skipped, failed
        /// Taken back by an undo run (FS-19.08 §6b): on the run's own row,
        /// the photo is back where it was; on an undo run's row, the undo
        /// of it is done.
        case undone
    }

    /// One source holding the bytes, as the scan saw it.
    struct Source: Codable, Hashable, Sendable {
        var path: String
        var size: Int64
        /// Write time at the scan, epoch seconds; re-asked before a delete.
        var modifiedAt: Int?
        /// The `.xmp` beside it, which follows the photo.
        var sidecar: String?
        /// Removed by this run (Move).
        var isRemoved = false
    }

    /// Why a photo was skipped or failed, stored as a code and worded when
    /// shown, so the log and the CSV follow the app's language.
    enum Reason: String, Sendable {
        case alreadyThere, changedOnServer, checksumMismatch, noSource, unreadableRecord
        /// The photo is in place; its `.xmp` is not (name taken by other
        /// bytes, or the copy failed).
        case sidecarNotCopied
        /// Undo (FS-19.08 §6b): no source copy is left, so the one in the
        /// destination stays — the last copy is never removed.
        case noOtherCopy
        /// Undo: the copy in the destination is not the bytes the run put
        /// there; nothing is put back or removed.
        case changedInShared
        /// Undo: a source's old path holds other bytes; that copy is not
        /// put back. The detail names the path.
        case nameTaken
        /// The server's own words follow the code: `serverError:<text>`.
        case serverError
    }

    var runId: String
    var position: Int
    var sha256: String
    var size: Int64
    /// First folder first.
    var sources: [Source]
    var status: Status
    var destinationPath: String?
    var partPath: String?
    var movedFrom: String?
    var reason: String?
    /// The `.xmp` this run wrote beside the photo in the destination, set
    /// before the write and cleared if it fails, with its SHA-256: undo
    /// removes only a sidecar the run put there.
    var sidecarPlaced: String?
    var sidecarSHA256: String?
    /// The destination already held these bytes before the run (Skipped,
    /// or a Move that removed every source): that file is not the run's,
    /// and undo never removes it. Kept apart from `reason`, which a later
    /// step may overwrite.
    var destinationWasThere = false
    var updatedAt: Int

    init(runId: String, position: Int, sha256: String, size: Int64, sources: [Source], status: Status = .pending,
         destinationPath: String? = nil, partPath: String? = nil, movedFrom: String? = nil, reason: String? = nil,
         updatedAt: Int = Int(Date().timeIntervalSince1970)) {
        self.runId = runId
        self.position = position
        self.sha256 = sha256
        self.size = size
        self.sources = sources
        self.status = status
        self.destinationPath = destinationPath
        self.partPath = partPath
        self.movedFrom = movedFrom
        self.reason = reason
        self.updatedAt = updatedAt
    }

    /// The reason code, and the server's words for `serverError`.
    var failure: (reason: Reason, detail: String?)? {
        guard let reason else { return nil }
        let parts = reason.split(separator: ":", maxSplits: 1).map(String.init)
        guard let code = Reason(rawValue: parts[0]) else { return (.serverError, reason) }
        return (code, parts.count > 1 ? parts[1] : nil)
    }

    static func reason(_ code: Reason, _ detail: String? = nil) -> String {
        detail.map { "\(code.rawValue):\($0)" } ?? code.rawValue
    }

    /// Done: nothing is left to do for it on Resume.
    var isDone: Bool { [.copied, .moved, .skipped, .failed, .undone].contains(status) }

    /// What an undo can take back: a photo this run put in the destination.
    /// A Move that removed some copies and then failed counts too: the
    /// photo is whole in the destination and its removed copies can go back.
    var isUndoable: Bool {
        status == .copied || status == .moved
            || (status == .failed && destinationPath != nil && sources.contains(where: \.isRemoved))
    }
}

extension CommonPhotosItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "common_photo_items"

    /// Sources that cannot be read fail the photo with a reason instead of
    /// reading as "nothing left to remove": a Move would otherwise call it
    /// done and leave copies behind with no word in the log. An unknown
    /// status reads as pending, so Resume redoes the photo from the start —
    /// every step checks the server before it acts.
    init(row: Row) {
        runId = row["runId"]
        position = row["position"]
        sha256 = row["sha256"]
        size = row["size"]
        let decoded = (row["sources"] as String?)?.data(using: .utf8).flatMap { try? JSONDecoder().decode([Source].self, from: $0) }
        sources = decoded ?? []
        status = decoded == nil ? .failed : Status(rawValue: row["status"] ?? "") ?? .pending
        destinationPath = row["destinationPath"]
        partPath = row["partPath"]
        movedFrom = row["movedFrom"]
        reason = decoded == nil ? Reason.unreadableRecord.rawValue : row["reason"] as String?
        sidecarPlaced = row["sidecarPlaced"]
        sidecarSHA256 = row["sidecarSHA256"]
        destinationWasThere = row["destinationWasThere"] ?? false
        updatedAt = row["updatedAt"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["runId"] = runId
        container["position"] = position
        container["sha256"] = sha256
        container["size"] = size
        container["sources"] = (try? String(decoding: JSONEncoder().encode(sources), as: UTF8.self)) ?? "[]"
        container["status"] = status.rawValue
        container["destinationPath"] = destinationPath
        container["partPath"] = partPath
        container["movedFrom"] = movedFrom
        container["reason"] = reason
        container["sidecarPlaced"] = sidecarPlaced
        container["sidecarSHA256"] = sidecarSHA256
        container["destinationWasThere"] = destinationWasThere
        container["updatedAt"] = updatedAt
    }
}
