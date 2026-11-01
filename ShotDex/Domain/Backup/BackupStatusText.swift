import Foundation

/// The two lines and the button a job card shows (FS-22.02 §5). Pure, so the
/// wording of every state is a unit test.
struct BackupStatusText: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case ok, active, waiting, attention }
    enum Action: Equatable, Sendable { case pause, resume, retry, openSettings, editServer }

    var title: String
    var detail: String
    var tone: Tone
    var action: Action?
    /// 0…1 when a bar belongs under the title.
    var fraction: Double?

    struct Input: Sendable {
        var state: BackupJobState
        var progress: BackupProgress?
        /// Items with at least one file backed up.
        var backedUpItems: Int
        var connectionName: String
        var sourceName: String
        var now = Date()
        /// Bytes per second over the last stretch of the run, when known.
        var bytesPerSecond: Double?
    }

    static func make(_ input: Input) -> BackupStatusText {
        let state = input.state
        let left = max(0, (state.statusTotal ?? 0) - (state.statusDone ?? 0))
        switch state.status {
        case .watching:
            let items = input.backedUpItems.formatted()
            let checked = state.lastCheckedAt.map {
                let date = Date(timeIntervalSince1970: TimeInterval($0))
                return String(localized: "checked \(date.formatted(.relative(presentation: .named, unitsStyle: .wide)))", comment: "Backup card: when the source was last compared, e.g. 'checked 2 minutes ago'")
            }
            let detail = [String(localized: "\(items) items", comment: "Backup card: how many items are backed up"), checked].compactMap { $0 }.joined(separator: " · ")
            return BackupStatusText(title: String(localized: "Watching · Up to Date", comment: "Backup card: the job is current and watches for new photos"), detail: detail, tone: .ok)

        case .uploading:
            let p = input.progress ?? BackupProgress(done: state.statusDone ?? 0, total: state.statusTotal ?? 0)
            if p.phase == .checkingDestination {
                // Nothing is copied while the destination tree is listed
                // (FS-22.05 §3, §5).
                return BackupStatusText(
                    title: String(localized: "Checking \(input.connectionName) · \(p.listedCount.formatted()) files", comment: "Backup card: listing what the destination folder already holds, e.g. 'Checking NAS Home · 12,408 files'"),
                    detail: state.hasFinishedFirstRun
                        ? String(localized: "daily check", comment: "Backup card: the destination is listed again once a day")
                        : String(localized: "before the first copy", comment: "Backup card: the destination is listed before anything is copied"),
                    tone: .active, action: .pause
                )
            }
            let fraction = p.total > 0 ? Double(p.done) / Double(p.total) : 0
            let bytes = "\(p.bytesDone.formatted(.byteCount(style: .file))) of \(p.bytesTotal.formatted(.byteCount(style: .file)))"
            if p.isFirstRun {
                var parts = [String(localized: "\(p.done.formatted()) of \(p.total.formatted())", comment: "Backup card: files done of files to copy"), bytes]
                if let rate = input.bytesPerSecond, rate > 0 {
                    let minutes = max(1, Int((Double(p.bytesTotal - p.bytesDone) / rate / 60).rounded()))
                    parts.append(String(localized: "about \(minutes) min left", comment: "Backup card: time left estimate"))
                }
                return BackupStatusText(
                    title: String(localized: "Backing Up · \(Int((fraction * 100).rounded()))%", comment: "Backup card: first run, percent done"),
                    detail: parts.joined(separator: " · "), tone: .active, action: .pause, fraction: fraction
                )
            }
            return BackupStatusText(
                title: String(localized: "\(p.total) New · Uploading", comment: "Backup card: new files found while watching are being copied"),
                detail: "\(String(localized: "\(min(p.done + 1, p.total)) of \(p.total)", comment: "Backup card: which new file is being copied")) · \(bytes)",
                tone: .active, action: .pause, fraction: fraction
            )

        case .waitingForWiFi:
            return BackupStatusText(title: String(localized: "Waiting for Wi‑Fi", comment: "Backup card: Only on Wi-Fi is on and the device is not on Wi-Fi"),
                                    detail: String(localized: "\(left) new · Only on Wi‑Fi is on", comment: "Backup card: files waiting for Wi-Fi"), tone: .waiting)
        case .waitingToCharge:
            return BackupStatusText(title: String(localized: "Waiting to Charge", comment: "Backup card: Only While Charging is on and the device is not charging"),
                                    detail: String(localized: "\(left) new · Only While Charging is on", comment: "Backup card: files waiting for power"), tone: .waiting)
        case .waitingForStorage:
            return BackupStatusText(title: String(localized: "Waiting for Storage", comment: "Backup card: not enough free space on the device to download originals"),
                                    detail: String(localized: "Needs 2 GB free on this device", comment: "Backup card: free space needed"), tone: .waiting, action: .retry)
        case .unreachable:
            return BackupStatusText(title: String(localized: "Can't Reach \(input.connectionName)", comment: "Backup card: the server did not answer"),
                                    detail: String(localized: "\(left) new · will try again", comment: "Backup card: retried on the next check"), tone: .attention, action: .retry)
        case .signInFailed:
            return BackupStatusText(title: String(localized: "Can't Sign In to \(input.connectionName)", comment: "Backup card: the server refused the password"),
                                    detail: String(localized: "Check the user name and password.", comment: "Backup card: what to do after a refused sign-in"), tone: .attention, action: .editServer)
        case .destinationFull:
            return BackupStatusText(title: String(localized: "\(input.connectionName) Is Full", comment: "Backup card: the server has no room"),
                                    detail: String(localized: "Free up space on the server, then retry.", comment: "Backup card: what to do when the server is full"), tone: .attention, action: .retry)
        case .sourceOffline:
            return BackupStatusText(title: String(localized: "Source Offline", comment: "Backup card: the drive or folder being backed up is not connected"),
                                    detail: String(localized: "\(input.sourceName) isn't connected", comment: "Backup card: which source is away"), tone: .waiting)
        case .noPhotosAccess:
            return BackupStatusText(title: String(localized: "No Photos Access", comment: "Backup card: ShotDex may not read the photo library"),
                                    detail: String(localized: "Allow access in Settings to back up your library.", comment: "Backup card: how to fix no photo access"), tone: .attention, action: .openSettings)
        case .pausedByUser:
            return BackupStatusText(title: String(localized: "Paused", comment: "Backup card: paused"),
                                    detail: String(localized: "Paused by you. New photos wait until you resume.", comment: "Backup card: the user paused the job"), tone: .waiting, action: .resume,
                                    fraction: pausedFraction(state))
        case .pausedBySystem:
            return BackupStatusText(title: String(localized: "Paused", comment: "Backup card: paused"),
                                    detail: String(localized: "iOS stopped ShotDex at \((state.statusDone ?? 0).formatted()) of \((state.statusTotal ?? 0).formatted()). Resumes from there.", comment: "Backup card: iOS ended the background run"),
                                    tone: .waiting, action: .resume, fraction: pausedFraction(state))
        }
    }

    private static func pausedFraction(_ state: BackupJobState) -> Double? {
        guard let total = state.statusTotal, total > 0 else { return nil }
        return Double(state.statusDone ?? 0) / Double(total)
    }
}

extension BackupStatusText.Action {
    var title: String {
        switch self {
        case .pause: String(localized: "Pause", comment: "Backup: pause the job")
        case .resume: String(localized: "Resume", comment: "Backup: resume the job")
        case .retry: String(localized: "Retry", comment: "Backup: try again")
        case .openSettings: String(localized: "Open Settings", comment: "Backup: open the Settings app")
        case .editServer: String(localized: "Edit Server", comment: "Backup: fix the connection")
        }
    }
}
