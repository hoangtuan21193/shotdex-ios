import Foundation
import GRDB

/// A set the helper gathers on its own every 15 minutes (FS-19.08 §6c,
/// Keep gathering).
struct CommonPhotosWatch: Equatable, Sendable, Identifiable {
    /// Why it does not gather any more until turned on again.
    enum Stop: Equatable, Sendable {
        /// A source folder or the destination is not on the server: path.
        case folderGone(String)
        /// The connection was removed from ShotDex.
        case connectionGone
        /// Not a set any more (fewer than two folders, the destination
        /// inside one), or a row this build cannot read.
        case cannotGather
    }

    var id: String
    var connectionId: String
    var folders: [String]
    var destination: String
    var action: CommonPhotosRun.Action
    var isOn: Bool
    var checkedAt: Date?
    var waiting: OnServerSchedule.Wait?
    var stopped: Stop?

    var setKey: String {
        CommonPhotosIncremental.setKey(connectionId: connectionId, folders: folders, destination: destination)
    }
}

/// Reads and writes `common_photo_watches`.
struct CommonPhotosWatchStore: Sendable {
    let database: AppDatabase

    /// Turns gathering on for a set, or changes its action; a set stopped
    /// for a missing folder starts again.
    struct NotASet: Error, Equatable {}

    @discardableResult
    func keepGathering(connectionId: String, folders: [String], destination: String, action: CommonPhotosRun.Action,
                       at now: Date = Date()) throws -> CommonPhotosWatch {
        guard CommonPhotosSelection.problem(folders: folders, destination: destination) == nil else { throw NotASet() }
        let key = CommonPhotosIncremental.setKey(connectionId: connectionId, folders: folders, destination: destination)
        return try database.writer.write { db in
            let id = try String.fetchOne(db, sql: "SELECT id FROM common_photo_watches WHERE setKey = ?", arguments: [key])
                ?? UUID().uuidString
            try db.execute(sql: """
                INSERT INTO common_photo_watches (id, setKey, connectionId, folders, destination, action, isOn, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                ON CONFLICT(setKey) DO UPDATE SET connectionId = excluded.connectionId, folders = excluded.folders,
                    destination = excluded.destination, action = excluded.action, isOn = 1, stoppedBecause = NULL, waiting = NULL
                """, arguments: [id, key, connectionId, Self.encode(folders), destination, action.rawValue,
                                 Int(now.timeIntervalSince1970)])
            guard let watch = try Self.watch(db, id: id) else { throw NotASet() }
            return watch
        }
    }

    /// Stop Gathering: no pass runs for it any more. Its runs, logs and
    /// files are left as they are.
    func stopGathering(id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE common_photo_watches SET isOn = 0, waiting = NULL WHERE id = ?", arguments: [id])
        }
    }

    func watches() throws -> [CommonPhotosWatch] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM common_photo_watches ORDER BY createdAt, id").map(Self.watch)
        }
    }

    func watch(id: String) throws -> CommonPhotosWatch? {
        try database.reader.read { db in try Self.watch(db, id: id) }
    }

    /// The set's watch, if it has one.
    func watch(connectionId: String, folders: [String], destination: String) throws -> CommonPhotosWatch? {
        let key = CommonPhotosIncremental.setKey(connectionId: connectionId, folders: folders, destination: destination)
        return try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM common_photo_watches WHERE setKey = ?", arguments: [key]).map(Self.watch)
        }
    }

    // A pass writes only while the set is on: a Stop Gathering or a
    // turn-on made during the pass wins over what the pass saw.

    /// Whether the set is still gathered.
    func isOn(id: String) throws -> Bool {
        try database.reader.read { db in
            try Bool.fetchOne(db, sql: "SELECT isOn FROM common_photo_watches WHERE id = ?", arguments: [id]) ?? false
        }
    }

    /// A pass looked: when, and what it waits for now (nil: nothing).
    func checked(id: String, at now: Date, waiting: OnServerSchedule.Wait?) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE common_photo_watches SET checkedAt = ?, waiting = ? WHERE id = ? AND isOn = 1",
                           arguments: [Int(now.timeIntervalSince1970), waiting.map(Self.code), id])
        }
    }

    /// A pass that could not start: what it waits for; the last check
    /// stays as it was.
    func waits(id: String, for wait: OnServerSchedule.Wait) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE common_photo_watches SET waiting = ? WHERE id = ? AND isOn = 1",
                           arguments: [Self.code(wait), id])
        }
    }

    /// Gathering stops until the user turns it on again.
    func stop(id: String, because stop: CommonPhotosWatch.Stop) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE common_photo_watches SET isOn = 0, waiting = NULL, stoppedBecause = ? WHERE id = ? AND isOn = 1",
                           arguments: [Self.code(stop), id])
        }
    }

    // MARK: Rows

    private static func watch(_ db: Database, id: String) throws -> CommonPhotosWatch? {
        try Row.fetchOne(db, sql: "SELECT * FROM common_photo_watches WHERE id = ?", arguments: [id]).map(watch)
    }

    /// A row this build cannot read (folders, action) is kept and shown as
    /// stopped — still listed, so it can be removed — and never gathers.
    private static func watch(_ row: Row) -> CommonPhotosWatch {
        let folders = decode(row["folders"])
        let action = CommonPhotosRun.Action(rawValue: row["action"] ?? "")
        guard let folders, let action else {
            return CommonPhotosWatch(id: row["id"], connectionId: row["connectionId"], folders: [], destination: row["destination"],
                                     action: .copy, isOn: false, checkedAt: nil, waiting: nil, stopped: .cannotGather)
        }
        return CommonPhotosWatch(id: row["id"], connectionId: row["connectionId"], folders: folders, destination: row["destination"],
                                 action: action, isOn: row["isOn"],
                                 checkedAt: (row["checkedAt"] as Int?).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                 waiting: (row["waiting"] as String?).flatMap(wait), stopped: (row["stoppedBecause"] as String?).flatMap(stop))
    }

    private static func encode(_ list: [String]) -> String {
        (try? String(decoding: JSONEncoder().encode(list), as: UTF8.self)) ?? "[]"
    }

    private static func decode(_ text: String?) -> [String]? {
        text.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) }
    }

    private static func code(_ wait: OnServerSchedule.Wait) -> String {
        switch wait {
        case .wifi: "wifi"
        case .charging: "charging"
        case .space: "space"
        case .openApp: "openApp"
        case .unreachable(let name): "unreachable:" + name
        }
    }

    private static func wait(_ code: String) -> OnServerSchedule.Wait? {
        if code.hasPrefix("unreachable:") { return .unreachable(String(code.dropFirst("unreachable:".count))) }
        return switch code {
        case "wifi": .wifi
        case "charging": .charging
        case "space": .space
        case "openApp": .openApp
        default: nil
        }
    }

    private static func code(_ stop: CommonPhotosWatch.Stop) -> String {
        switch stop {
        case .folderGone(let path): "folderGone:" + path
        case .connectionGone: "connectionGone"
        case .cannotGather: "cannotGather"
        }
    }

    private static func stop(_ code: String) -> CommonPhotosWatch.Stop? {
        if code == "connectionGone" { return .connectionGone }
        if code == "cannotGather" { return .cannotGather }
        return code.hasPrefix("folderGone:") ? .folderGone(String(code.dropFirst("folderGone:".count))) : nil
    }
}
