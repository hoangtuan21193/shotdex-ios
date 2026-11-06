import Foundation
import GRDB

/// One common-photos run (FS-19.08 §8): the folders compared, where the
/// shared photos go, Copy or Move, and how far it got.
struct CommonPhotosRun: Hashable, Sendable, Identifiable {
    enum Action: String, Sendable { case copy, move }

    enum State: String, Sendable {
        /// Photos listed, nothing placed yet or partway through.
        case running
        /// The user paused it, or the connection went away.
        case paused
        /// The user stopped it; what is done stays done.
        case stopped
        /// Every photo done; the CSV, the rescan and the history repair
        /// are not yet — a quit here resumes them.
        case finishing
        case finished
        /// Keep gathering found photos for a Move set (FS-19.08 §6c):
        /// listed, nothing moved or removed until the user says Move. Not
        /// unfinished — no Resume, nothing runs it on its own.
        case ready
    }

    var id: String
    var connectionId: String
    var folders: [String]
    var destination: String
    var action: Action
    var state: State
    var createdAt: Int
    var updatedAt: Int
    var csvPath: String?
    /// The run this one undoes (FS-19.08 §6b); nil for a run that gathers.
    /// Folders, destination and action are the undone run's.
    var undoOf: String?
    /// Keep gathering (FS-19.08 §6c): the set's watch and the day this run
    /// gathers for; nil for a run started from the sheet.
    var watchId: String?
    var day: String?
    /// How the run files photos in the destination (FS-19.08 §6e); nil = all
    /// at its top under their own names, as before §6e.
    var organize: BackupOrganize?
    /// The folders under the destination this run made for Organize,
    /// relative to it (§6e): what an undo removes again when it leaves them
    /// empty.
    var createdFolders: [String] = []
    /// False when a stored value could not be read back (folders, action):
    /// the banner offers Discard only, never Resume. Not stored.
    var isReadable = true

    init(id: String = UUID().uuidString, connectionId: String, folders: [String], destination: String,
         action: Action, state: State = .running, createdAt: Int = Int(Date().timeIntervalSince1970), csvPath: String? = nil,
         undoOf: String? = nil) {
        self.id = id
        self.connectionId = connectionId
        self.folders = folders
        self.destination = destination
        self.action = action
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.csvPath = csvPath
        self.undoOf = undoOf
    }

    /// Whether the next launch offers Resume · Discard (FS-19.08 §7).
    var isUnfinished: Bool { [.running, .paused, .finishing].contains(state) }

    /// Whether Resume can carry on from what is stored.
    var canResume: Bool { isUnfinished && isReadable && folders.count >= 2 }

    var isUndo: Bool { undoOf != nil }

    /// Over: what is done stays done, and an undo may take it back.
    var isOver: Bool { state == .finished || state == .stopped }
}

extension CommonPhotosRun: FetchableRecord, PersistableRecord {
    static let databaseTableName = "common_photo_runs"

    /// An unreadable value falls back rather than failing the row: a run
    /// the app cannot read must still be listed so it can be discarded. An
    /// unknown state reads as paused (listed, unfinished); unknown folders or
    /// action make it Discard only — never a Move quietly resumed as a Copy.
    init(row: Row) {
        id = row["id"]
        connectionId = row["connectionId"]
        let decodedFolders = JSONList.decode(row["folders"])
        folders = decodedFolders ?? []
        destination = row["destination"]
        let decodedAction = Action(rawValue: row["action"] ?? "")
        action = decodedAction ?? .copy
        state = State(rawValue: row["state"] ?? "") ?? .paused
        isReadable = decodedFolders != nil && decodedAction != nil
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
        csvPath = row["csvPath"]
        undoOf = row["undoOf"]
        watchId = row["watchId"]
        day = row["day"]
        // An Organize that cannot be read makes the run Discard only, as
        // unreadable folders do: its pending photos must not land at the top
        // beside the ones already filed.
        createdFolders = JSONList.decode(row["createdFolders"]) ?? []
        if let text = row["organize"] as String? {
            organize = try? JSONDecoder().decode(BackupOrganize.self, from: Data(text.utf8))
            if organize == nil { isReadable = false }
        }
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["connectionId"] = connectionId
        container["folders"] = JSONList.encode(folders)
        container["destination"] = destination
        container["action"] = action.rawValue
        container["state"] = state.rawValue
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
        container["csvPath"] = csvPath
        container["undoOf"] = undoOf
        container["watchId"] = watchId
        container["day"] = day
        container["createdFolders"] = createdFolders.isEmpty ? nil : JSONList.encode(createdFolders)
        container["organize"] = organize.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) }
    }
}


/// A list of strings in one TEXT column.
private enum JSONList {
    static func encode(_ list: [String]) -> String {
        (try? String(decoding: JSONEncoder().encode(list), as: UTF8.self)) ?? "[]"
    }

    /// Nil when the column holds something else.
    static func decode(_ text: String?) -> [String]? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
