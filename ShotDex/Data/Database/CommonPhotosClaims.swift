import Foundation
import GRDB

/// Who runs what across processes (FS-19.08 §6c): the Mac app and its
/// helper open one database, and either may run a common-photos run or a
/// Keep-gathering pass. A claim is a row's `claimedBy` (this process) and
/// `claimedAt`; it holds while renewed, and one not renewed for
/// `expiresAfter` is free — a process that died leaves nothing locked.
struct CommonPhotosClaims: Sendable {
    let database: AppDatabase
    /// This process, for as long as it runs.
    static let me = UUID().uuidString
    /// Who claims: this process (a test stands in for the other one).
    var owner = CommonPhotosClaims.me
    static let expiresAfter: TimeInterval = 120
    /// Well inside the expiry, so a busy process never loses its claim.
    static let renewEvery: Duration = .seconds(30)

    enum Table: String, Sendable {
        case run = "common_photo_runs"
        case watch = "common_photo_watches"
    }

    /// Takes `id` for this process; false when another holds it.
    func claim(_ table: Table, id: String, now: Date = Date()) -> Bool {
        let time = Int(now.timeIntervalSince1970)
        return (try? database.writer.write { db in
            try db.execute(sql: """
                UPDATE \(table.rawValue) SET claimedBy = ?, claimedAt = ?
                WHERE id = ? AND (claimedBy IS NULL OR claimedBy = ? OR claimedAt < ?)
                """, arguments: [owner, time, id, owner, time - Int(Self.expiresAfter)])
            return db.changesCount > 0
        }) ?? false
    }

    /// Still ours: the claim lives on. False when it was taken meanwhile.
    @discardableResult
    func renew(_ table: Table, id: String, now: Date = Date()) -> Bool {
        (try? database.writer.write { db in
            try db.execute(sql: "UPDATE \(table.rawValue) SET claimedAt = ? WHERE id = ? AND claimedBy = ?",
                           arguments: [Int(now.timeIntervalSince1970), id, owner])
            return db.changesCount > 0
        }) ?? false
    }

    func release(_ table: Table, id: String) {
        _ = try? database.writer.write { db in
            try db.execute(sql: "UPDATE \(table.rawValue) SET claimedBy = NULL, claimedAt = NULL WHERE id = ? AND claimedBy = ?",
                           arguments: [id, owner])
        }
    }

    /// Another live process holds it.
    func isClaimedElsewhere(_ table: Table, id: String, now: Date = Date()) -> Bool {
        let row = try? database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT claimedBy, claimedAt FROM \(table.rawValue) WHERE id = ?", arguments: [id])
        }
        guard let row, let by: String = row["claimedBy"], by != owner, let at: Int = row["claimedAt"] else { return false }
        return at >= Int(now.timeIntervalSince1970) - Int(Self.expiresAfter)
    }
}
