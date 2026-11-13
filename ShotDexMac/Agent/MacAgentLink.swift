import Foundation
import notify
import ServiceManagement

/// The line between the app and its helper (FS-22.06 §2–§3). The helper is
/// this same executable started by launchd with `--agent`, registered as a
/// LaunchAgent so it keeps running Backup after the app quits.
///
/// - App → helper: commands in the app group's defaults, then a Darwin
///   notification.
/// - Helper → app: job states in the shared database, the live run in the
///   app group's defaults, then a Darwin notification.
enum MacAgentLink {
    static let plistName = "com.hoangtuan.shotdex.agent.plist"
    static let agentArgument = "--agent"
    /// Darwin notification names, scoped by the app group.
    static let commandsPosted = "\(AppDatabase.macAppGroup).agent.commands"
    static let agentChanged = "\(AppDatabase.macAppGroup).agent.changed"
    static let onServerChanged = "\(AppDatabase.macAppGroup).agent.onServer"
    /// Keep gathering changed a set or a run (FS-19.08 §6c): read again.
    static let commonPhotosChanged = "\(AppDatabase.macAppGroup).agent.commonPhotos"

    private static let commandsKey = "agentCommands"
    private static let runKey = "agentRun"
    private static let heartbeatKey = "agentHeartbeat"
    private static let keepsWorkingKey = "agentKeepsWorkingAfterQuit"
    private static let onServerKey = "agentOnServer"

    static var defaults: UserDefaults { UserDefaults(suiteName: AppDatabase.macAppGroup) ?? .standard }
    static var service: SMAppService { SMAppService.agent(plistName: plistName) }

    // MARK: Commands

    /// `checkOnServer`: the app came forward — list the servers again
    /// (FS-19.07 §5) and hash what is left.
    /// `gatherNow` (jobId: a Keep-gathering set's id), `watchesChanged`: a
    /// set was turned on or off (FS-19.08 §6c).
    enum Action: String { case pause, resume, backUpNow, retry, jobsChanged, start, checkOnServer, gatherNow, watchesChanged }

    struct Command: Equatable {
        var action: Action
        var jobId: String?
    }

    static func post(_ command: Command) {
        var list = defaults.array(forKey: commandsKey) as? [[String: String]] ?? []
        var entry = ["action": command.action.rawValue]
        entry["jobId"] = command.jobId
        list.append(entry)
        defaults.set(list, forKey: commandsKey)
        notify_post(commandsPosted)
    }

    /// The helper's side: every command since the last call, oldest first.
    static func takeCommands() -> [Command] {
        let list = defaults.array(forKey: commandsKey) as? [[String: String]] ?? []
        defaults.removeObject(forKey: commandsKey)
        return list.compactMap { entry in
            entry["action"].flatMap(Action.init(rawValue:)).map { Command(action: $0, jobId: entry["jobId"]) }
        }
    }

    static func postCommonPhotosChanged() { notify_post(commonPhotosChanged) }
    /// The helper took a click on a Keep-gathering notice for the running app.
    static let noticeClicked = "\(AppDatabase.macAppGroup).agent.noticeClicked"
    static func post(noticeClicked: Void) { notify_post(Self.noticeClicked) }

    // MARK: The run in flight

    struct Run: Equatable {
        var jobId: String
        var progress: BackupProgress
        var bytesPerSecond: Double?
    }

    static func publish(_ run: Run?) {
        if let run {
            var entry: [String: Any] = [
                "jobId": run.jobId, "done": run.progress.done, "total": run.progress.total,
                "bytesDone": run.progress.bytesDone, "bytesTotal": run.progress.bytesTotal,
                "isFirstRun": run.progress.isFirstRun, "failed": run.progress.failed,
            ]
            entry["file"] = run.progress.currentFile
            entry["bytesPerSecond"] = run.bytesPerSecond
            defaults.set(entry, forKey: runKey)
        } else {
            defaults.removeObject(forKey: runKey)
        }
        notify_post(agentChanged)
    }

    static func currentRun() -> Run? {
        guard let entry = defaults.dictionary(forKey: runKey), let jobId = entry["jobId"] as? String else { return nil }
        var progress = BackupProgress()
        progress.done = entry["done"] as? Int ?? 0
        progress.total = entry["total"] as? Int ?? 0
        progress.bytesDone = (entry["bytesDone"] as? NSNumber)?.int64Value ?? 0
        progress.bytesTotal = (entry["bytesTotal"] as? NSNumber)?.int64Value ?? 0
        progress.isFirstRun = entry["isFirstRun"] as? Bool ?? false
        progress.failed = entry["failed"] as? Int ?? 0
        progress.currentFile = entry["file"] as? String
        return Run(jobId: jobId, progress: progress, bytesPerSecond: entry["bytesPerSecond"] as? Double)
    }

    // MARK: The On Server check (FS-19.07 §11)

    /// What the helper's check waits for and when it last finished; the
    /// counts themselves are in the shared database.
    struct OnServerState: Equatable {
        var waits: [String: OnServerSchedule.Wait] = [:]
        var photosWait: OnServerSchedule.Wait?
        var finishedAt: Date?
        var isRunning = false
        var stage: OnServerCheck.Stage?
        /// The helper's batch count: a new one makes the app read the counts again.
        var batch = 0
    }

    static func publish(_ state: OnServerState) {
        var entry: [String: Any] = ["waits": state.waits.mapValues(encode), "isRunning": state.isRunning]
        entry["photosWait"] = state.photosWait.map(encode)
        entry["finishedAt"] = state.finishedAt?.timeIntervalSince1970
        entry["stage"] = state.stage?.rawValue
        entry["batch"] = state.batch
        defaults.set(entry, forKey: onServerKey)
        notify_post(onServerChanged)
    }

    static func currentOnServer() -> OnServerState {
        guard let entry = defaults.dictionary(forKey: onServerKey) else { return OnServerState() }
        return OnServerState(
            waits: (entry["waits"] as? [String: String] ?? [:]).compactMapValues(decode),
            photosWait: (entry["photosWait"] as? String).flatMap(decode),
            finishedAt: (entry["finishedAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
            isRunning: entry["isRunning"] as? Bool ?? false,
            stage: (entry["stage"] as? String).flatMap(OnServerCheck.Stage.init(rawValue:)),
            batch: entry["batch"] as? Int ?? 0
        )
    }

    private static func encode(_ wait: OnServerSchedule.Wait) -> String {
        switch wait {
        case .wifi: "wifi"
        case .charging: "charging"
        case .space: "space"
        case .openApp: "openApp"
        case .iCloudRefusing: "iCloudRefusing"
        case .unreachable(let name): "unreachable:" + name
        }
    }

    private static func decode(_ text: String) -> OnServerSchedule.Wait? {
        if text.hasPrefix("unreachable:") { return .unreachable(String(text.dropFirst("unreachable:".count))) }
        return switch text {
        case "wifi": .wifi
        case "charging": .charging
        case "space": .space
        case "openApp": .openApp
        case "iCloudRefusing": .iCloudRefusing
        default: nil
        }
    }

    /// A server source exists, so the check has something to do — the
    /// helper's other reason to run besides Backup jobs (FS-22.06 §2).
    static func hasOnServerWork(_ database: AppDatabase) -> Bool {
        !((try? SourceStore(database: database).serverConnections()) ?? [:]).isEmpty
    }

    // MARK: Liveness and registration

    static func beat() { defaults.set(Date().timeIntervalSince1970, forKey: heartbeatKey) }

    /// The helper wrote a heartbeat in the last 5 seconds.
    static var isAgentAlive: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: heartbeatKey) < 5
    }

    /// Keep Working After Quit (FS-22.06 §5.4); on until the user turns it off.
    static var keepsWorkingAfterQuit: Bool {
        get { defaults.object(forKey: keepsWorkingKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keepsWorkingKey) }
    }

    /// The helper is the one running jobs: registered, allowed and alive.
    static var agentRunsJobs: Bool { service.status == .enabled && isAgentAlive }

    /// Register the helper when there is work for it, and start it again if
    /// it left (it quits when idle). Does nothing when the user turned it
    /// off or macOS wants approval first.
    static func ensureAgent(hasWork: Bool) {
        guard hasWork, keepsWorkingAfterQuit else { return }
        let service = service
        switch service.status {
        case .notRegistered, .notFound:
            try? service.register()
        case .enabled where !isAgentAlive:
            // launchd starts a LaunchAgent at load only; registering again
            // is how an app starts one that quit when it had nothing to do.
            Task {
                try? await service.unregister()
                try? service.register()
            }
        default:
            break
        }
    }

    /// Calls `handler` on the main queue each time `name` is posted.
    @discardableResult
    static func observe(_ name: String, handler: @escaping @MainActor () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, .main) { _ in MainActor.assumeIsolated { handler() } }
        return token
    }
}
