import Foundation

/// One long-running job as the Activity window lists it (FS-18.01 §4,
/// board `MAC_Activity`): what it is, how far, what it says, and what can be
/// done to it. A value, so every producer — common photos first — maps its
/// own state onto the same row, and the mapping is tested without a window.
struct LongRunningJob: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case commonPhotos
        /// An undo of a common-photos run (FS-19.08 §6b).
        case commonPhotosUndo
    }

    enum State: Equatable, Sendable {
        case running
        /// Every step done; the job is writing what it owes (a log, a rescan).
        case finishing
        /// Every step was done but what it owed was not written — a quit or
        /// a lost connection at the end. Resume writes it; Stop is not offered,
        /// since what moved must still be logged.
        case owesFinish
        /// The user paused it.
        case paused
        /// It stopped without being asked: a lost connection, a quit, a crash.
        case interrupted
        /// The user ended it for good.
        case stopped
        case done
        /// Done, with some items that could not be done.
        case doneWithFailures
    }

    enum Action: Equatable, Sendable {
        case pause, resume, stop, tryAgain, showLog
        /// Remove from List… (FS-19.08 §6b): the run and its log go after a
        /// question; it can no longer be undone.
        case remove
    }

    let id: String
    let kind: Kind
    let title: String
    /// Right of the title: the percentage while it goes, when it ended after.
    let aside: String
    /// Nil once over: no bar.
    let fraction: Double?
    let status: String
    let detail: String?
    let state: State
    let actions: [Action]

    var isOver: Bool { [.done, .doneWithFailures, .stopped].contains(state) }
    /// The order the list keeps: going first, then waiting, then over.
    var rank: Int {
        switch state {
        case .running, .finishing: 0
        case .paused, .interrupted, .owesFinish: 1
        case .stopped, .done, .doneWithFailures: 2
        }
    }
}

/// A common-photos run as an Activity row (FS-19.08 §7).
enum CommonPhotosJob {
    struct Input: Sendable {
        var run: CommonPhotosRun
        var progress: CommonPhotosRunner.Progress
        var isRunning: Bool
        var isPausedByUser: Bool
        /// Why it stopped short, in the connection's words.
        var problem: String?
        /// Copied or moved — for an undo run (`run.isUndo`), undone; its
        /// `failed` are the rows not undone.
        var copiedOrMoved = 0
        var skipped = 0
        var failed = 0
        /// Of a gathering run's photos, how many an undo took back since.
        var undone = 0
        var secondsLeft: Double?
        /// When it ended, for the aside of a row that is over.
        var endedAt: Date?
    }

    static func job(_ input: Input, now: Date = Date()) -> LongRunningJob {
        let run = input.run
        let progress = input.progress
        let folders = run.folders.map { ServerUploadPath.lastComponent(of: $0) }.joined(separator: " + ")
        let destination = ServerUploadPath.lastComponent(of: run.destination)
        let kind: LongRunningJob.Kind = run.isUndo ? .commonPhotosUndo : .commonPhotos
        let title = run.isUndo
            ? String(localized: "Undo · \(destination) → \(folders)", comment: "Activity: an undo of a common-photos run")
            : String(localized: "Common photos · \(folders) → \(destination)", comment: "Activity: a common-photos run")
        let fraction = progress.totalBytes > 0 ? min(1, Double(progress.doneBytes) / Double(progress.totalBytes))
            : (progress.totalCount > 0 ? Double(progress.doneCount) / Double(progress.totalCount) : 0)
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        let ofTotal = String(localized: "\(progress.doneCount.formatted()) of \(progress.totalCount.formatted())", comment: "Activity: N of M photos")
        let counts = run.isUndo
            ? [String(localized: "\(input.copiedOrMoved.formatted()) undone", comment: "Activity: count"),
               String(localized: "\(input.failed.formatted()) not undone", comment: "Activity: count")].joined(separator: " · ")
            : [run.action == .move ? String(localized: "\(input.copiedOrMoved.formatted()) moved", comment: "Activity: count")
                                   : String(localized: "\(input.copiedOrMoved.formatted()) copied", comment: "Activity: count"),
               String(localized: "\(input.skipped.formatted()) skipped", comment: "Activity: count"),
               String(localized: "\(input.failed.formatted()) failed", comment: "Activity: count")]
              .joined(separator: " · ") + (input.undone > 0
                  ? " · " + String(localized: "\(input.undone.formatted()) undone", comment: "Activity: count of a run's photos taken back since")
                  : "")
        let ended = input.endedAt.map { $0.formatted(.relative(presentation: .named)) } ?? ""

        let state: LongRunningJob.State = switch run.state {
        case .finished: input.failed > 0 ? .doneWithFailures : .done
        case .stopped: .stopped
        case .finishing: input.isRunning ? .finishing : .owesFinish
        default: input.isRunning ? .running : (input.isPausedByUser ? .paused : .interrupted)
        }

        switch state {
        case .running:
            let position = String(localized: "\(min(progress.doneCount + 1, progress.totalCount).formatted()) of \(progress.totalCount.formatted())",
                                  comment: "Activity: photo N of M")
            let bytes = String(localized: "\(progress.doneBytes.formatted(.byteCount(style: .file))) of \(progress.totalBytes.formatted(.byteCount(style: .file)))",
                               comment: "Activity: bytes done of total")
            var status = run.isUndo
                ? String(localized: "Undoing \(position) · \(bytes)", comment: "Activity: an undo going")
                : run.action == .move
                ? String(localized: "Moving \(position) · \(bytes)", comment: "Activity: a Move going")
                : String(localized: "Copying \(position) · \(bytes)", comment: "Activity: a Copy going")
            if let seconds = input.secondsLeft, seconds >= 1 { status += " · " + timeLeft(seconds) }
            let detail = progress.currentName.flatMap { name in
                progress.currentStep.map { "\(name) · \(words($0, destination: destination, isUndo: run.isUndo))" }
            }
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: percent, fraction: fraction, status: status,
                                  detail: detail, state: state, actions: [.pause, .stop, .showLog])
        case .finishing:
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: percent, fraction: fraction,
                                  status: String(localized: "Writing the log and rescanning…", comment: "Activity: a run finishing"),
                                  detail: nil, state: state, actions: [.showLog])
        case .owesFinish:
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: percent, fraction: fraction,
                                  status: String(localized: "Writing the log — Resume finishes it", comment: "Activity: a run left before its log and rescan"),
                                  detail: input.problem, state: state, actions: run.isReadable ? [.resume, .showLog] : [.showLog])
        case .paused:
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: percent, fraction: fraction,
                                  status: String(localized: "Paused at \(ofTotal)", comment: "Activity: a run the user paused"),
                                  detail: nil, state: state, actions: run.canResume ? [.resume, .stop, .showLog] : [.showLog])
        case .interrupted:
            let status = input.problem.map {
                String(localized: "Interrupted — \($0) · \(ofTotal) done", comment: "Activity: a run a connection error stopped")
            } ?? String(localized: "Interrupted at \(ofTotal)", comment: "Activity: a run a quit or crash stopped")
            let actions: [LongRunningJob.Action] = run.canResume
                ? [input.problem == nil ? .resume : .tryAgain, .stop, .showLog]
                : [.showLog]
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: percent, fraction: fraction, status: status,
                                  detail: nil, state: state, actions: actions)
        case .stopped:
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: ended, fraction: nil,
                                  status: String(localized: "Stopped — \(counts)", comment: "Activity: a run the user stopped"),
                                  detail: nil, state: state, actions: [.showLog, .remove])
        case .done, .doneWithFailures:
            return LongRunningJob(id: run.id, kind: kind, title: title, aside: ended, fraction: nil,
                                  status: String(localized: "Done — \(counts)", comment: "Activity: a run that finished"),
                                  detail: nil, state: state, actions: [.showLog, .remove])
        }
    }

    /// The step the run is on, as the window and Activity say it.
    static func words(_ step: CommonPhotosRunner.Progress.Step, destination: String, isUndo: Bool = false) -> String {
        if isUndo {
            return switch step {
            case .checking: String(localized: "checking the copies", comment: "Common photos undo: current step")
            case .downloading: String(localized: "downloading from \(destination)", comment: "Common photos undo: current step")
            case .uploading: String(localized: "putting it back", comment: "Common photos undo: current step")
            case .readingBack: String(localized: "reading back SHA-256", comment: "Common photos undo: current step")
            case .moving: String(localized: "moving it back", comment: "Common photos undo: current step")
            case .removing: String(localized: "removing it from \(destination)", comment: "Common photos undo: current step")
            }
        }
        return switch step {
        case .checking: String(localized: "checking it hasn't changed", comment: "Common photos: current step")
        case .downloading: String(localized: "downloading", comment: "Common photos: current step")
        case .uploading: String(localized: "uploading to \(destination)", comment: "Common photos: current step")
        case .readingBack: String(localized: "reading back SHA-256 in \(destination)", comment: "Common photos: current step")
        case .moving: String(localized: "moving to \(destination)", comment: "Common photos: current step")
        case .removing: String(localized: "removing the other copies", comment: "Common photos: current step")
        }
    }

    /// "about 4 min left".
    static func timeLeft(_ seconds: Double) -> String {
        let left = Duration.seconds(seconds.rounded())
        let style: Duration.UnitsFormatStyle = .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        return String(localized: "about \(left.formatted(style)) left", comment: "Common photos: time left")
    }
}
