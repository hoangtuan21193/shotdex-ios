import Foundation

/// One set Keep gathering runs, as the Gathering section of Activity lists
/// it (FS-19.08 §6c, board `MAC_Activity`): its folders, Copy or Move, and
/// what the last pass said. A value, tested without a window.
struct CommonPhotosWatchRow: Identifiable, Equatable, Sendable {
    enum Action: Hashable, Sendable {
        case runNow, stopGathering
        /// A set that stopped by itself (a folder gone): off the list.
        case remove
    }

    let id: String
    /// "Tuấn + Vợ → Shared".
    let title: String
    /// "Copy · checked 3 min ago · 128 gathered".
    let detail: String
    /// It stopped by itself: the line is a warning.
    let isStopped: Bool
    /// A Move set: what it finds waits for the user.
    var isMove = false
    let actions: [Action]

    /// A set turned off by the user is not listed (nil): its runs stay in
    /// Activity, the set does not.
    static func make(_ watch: CommonPhotosWatch, connectionName: String, gathered: Int, readyToMove: Int,
                     now: Date = Date()) -> CommonPhotosWatchRow? {
        let folders = watch.folders.map { ServerUploadPath.lastComponent(of: $0) }.joined(separator: " + ")
        let destination = ServerUploadPath.lastComponent(of: watch.destination)
        let title = folders.isEmpty ? destination : "\(folders) → \(destination)"
        if let stop = watch.stopped {
            let why = switch stop {
            case .folderGone(let path):
                String(localized: "“\(ServerUploadPath.lastComponent(of: path))” isn’t on \(connectionName) anymore",
                       comment: "Activity, Gathering: a folder of the set was removed on the server")
            case .connectionGone:
                String(localized: "The connection was removed", comment: "Activity, Gathering: the set's connection is gone")
            case .cannotGather:
                String(localized: "These folders can’t be gathered", comment: "Activity, Gathering: not a set any more, or a row this build cannot read")
            }
            let detail = why + " · " + String(localized: "Stopped gathering", comment: "Activity, Gathering: the set gathers no more until turned on again")
            return CommonPhotosWatchRow(id: watch.id, title: title, detail: detail, isStopped: true, actions: [.remove])
        }
        guard watch.isOn else { return nil }
        var parts = [watch.action == .move ? String(localized: "Move", comment: "Activity, Gathering: the set moves")
                                           : String(localized: "Copy", comment: "Activity, Gathering: the set copies")]
        if let wait = watch.waiting {
            parts.append(OnServerProgressLine.text(for: wait))
        } else if let checked = watch.checkedAt {
            let ago = checked.formatted(.relative(presentation: .named, unitsStyle: .wide))
            parts.append(String(localized: "checked \(ago)", comment: "Activity, Gathering: when the last pass looked, e.g. checked 3 minutes ago"))
        } else {
            parts.append(String(localized: "not checked yet", comment: "Activity, Gathering: no pass has looked yet"))
        }
        if watch.action == .move, readyToMove > 0 {
            parts.append(String(localized: "\(readyToMove.formatted()) ready to move", comment: "Activity, Gathering: photos waiting for Move N…"))
        } else if gathered > 0 {
            parts.append(String(localized: "\(gathered.formatted()) gathered", comment: "Activity, Gathering: photos the set has gathered so far"))
        }
        return CommonPhotosWatchRow(id: watch.id, title: title, detail: parts.joined(separator: " · "), isStopped: false,
                                    isMove: watch.action == .move, actions: [.runNow, .stopGathering])
    }
}
