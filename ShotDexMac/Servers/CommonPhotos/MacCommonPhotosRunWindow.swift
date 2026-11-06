import AppKit
import Observation
import SwiftUI

/// The window of one common-photos run (board `MAC_CommonPhotosRun`,
/// FS-19.08 §7): where it is, Pause · Stop, and a log of every photo. Its
/// own window, not modal; closing it never stops the run. Opened when Copy
/// or Move starts, from the sidebar foot and the browser's banner, and by
/// Activity's Show Log (`openWindow(id: MacCommonPhotosRunWindow.id, value: runId)`).
struct MacCommonPhotosRunWindow: View {
    static let id = "commonPhotosRun"
    /// Board `MAC_CommonPhotosRun`: the window at 900×560.
    static let size = CGSize(width: 1040, height: 560)

    /// Nil for a window macOS restored with no run to show.
    let runId: String?
    @Environment(MacDependencies.self) private var dependencies
    @State private var log: MacCommonPhotosLogModel?

    var body: some View {
        Group {
            if let runId, let log, let entry = dependencies.commonPhotos.entries[runId] {
                MacCommonPhotosRunContent(entry: entry, log: log)
            } else {
                ContentUnavailableView(String(localized: "No Run to Show", comment: "Common photos window: nothing to show"),
                                       systemImage: "doc.questionmark",
                                       description: Text("This run was discarded, or the window was left from an earlier session.",
                                                         comment: "Common photos window: why nothing shows"))
            }
        }
        // The board's width (FS-19.08 §6e added File info): below it Reason,
        // the column that explains a failure, is cut. A window saved
        // narrower opens at it.
        .frame(minWidth: Self.size.width, idealWidth: Self.size.width, minHeight: 420, idealHeight: Self.size.height)
        .tint(MacTheme.accent)
        .task(id: runId) {
            guard let runId, dependencies.commonPhotos.entry(for: runId) != nil else { return }
            log = MacCommonPhotosLogModel(runId: runId, store: dependencies.commonPhotos.store)
        }
        .onDisappear {
            if let runId { dependencies.commonPhotos.release(runId: runId) }
        }
    }
}

/// The log's rows, read from the store off the main actor — again at most
/// twice a second while the run moves, never per progress tick — with what
/// the table shows and the counts kept, not worked out per frame.
@MainActor
@Observable
final class MacCommonPhotosLogModel {
    struct Row: Identifiable, Equatable, Sendable {
        let id: Int
        let status: CommonPhotosItem.Status
        let statusText: String
        let name: String
        let from: String
        let to: String
        let shortSHA: String
        let reason: String
        /// §6e: Quick / Full; blank on skipped and undo rows.
        let check: String
        /// §6e: Kept / Dates not kept / Tags not kept / —.
        let fileInfo: String
        let datesLost: Bool
        // As the CSV writes them, for ⌘C.
        let csvStatus: String
        let csvReason: String
        let csvFileInfo: String
        let csvCheck: String
        let fromPaths: String
        let toPath: String
        let sha256: String
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, done, skipped, failed
        var id: Self { self }
    }

    struct Counts: Equatable {
        /// Copied or moved, undone since included — for an undo run, undone.
        var done = 0, skipped = 0, failed = 0
        /// §6e: copies that came back without their original dates.
        var datesLost = 0
        /// A gathering run's photos an undo took back since.
        var undone = 0
    }

    let runId: String
    private(set) var rows: [Row] = [] {
        didSet { counts = Self.counts(rows, isUndo: isUndo); reshow() }
    }
    /// The run is an undo: its done rows are the undone ones.
    private(set) var isUndo = false
    private(set) var shown: [Row] = []
    private(set) var counts = Counts()
    /// Rows an undo took back — a change re-asks whether Undo is offered.
    var undoneCount: Int { isUndo ? counts.done : counts.undone }
    /// The store's items as last read — the Move wording counts them.
    private(set) var items: [CommonPhotosItem] = []
    /// Copies Restore File Info… would set (FS-19.08 §6e), counted once per
    /// read: those that lost their dates, and those copied before dates
    /// were kept (a run from before §6e).
    private(set) var restorableLost = 0
    private(set) var restorableUnknown = 0
    /// §6d: SHA-256 of the photos the user left out of the run's set — a
    /// ready run's rows show them unchecked, and Move leaves them.
    private(set) var leftOut: Set<String> = []
    /// The run's set, for Left Out.
    private(set) var setKey: String?
    var filter = Filter.all { didSet { reshow() } }
    var sortOrder = [KeyPathComparator(\Row.id)] { didSet { reshow() } }
    var selection: Set<Int> = []
    /// The CSV the run left in the destination, once written.
    private(set) var csvName: String?
    /// The run's `updatedAt` when these rows were read (read first): Move
    /// N… moves only the list the user saw (§6c).
    private(set) var runUpdatedAt = 0

    @ObservationIgnored private let store: CommonPhotosStore
    private var connectionId = ""
    @ObservationIgnored private var readGeneration = 0

    /// §6d: checks or unchecks a photo of a ready run. Stored for the set
    /// at once; Move leaves what is unchecked, and no later pass lists it.
    func setLeftOut(_ isLeftOut: Bool, row: Row) {
        guard let setKey, let index = items.firstIndex(where: { $0.position == row.id }) else { return }
        // A Live Photo's halves go together (§6f).
        let pair = CommonPhotosRunner.livePair(items, at: index).map { items[$0] }
        // The box and the counts move at once; the read confirms.
        for item in pair {
            if isLeftOut { leftOut.insert(item.sha256) } else { leftOut.remove(item.sha256) }
        }
        let leftOutStore = CommonPhotosLeftOutStore(database: store.database)
        do {
            if isLeftOut {
                try leftOutStore.leaveOut(pair.map { .init(sha256: $0.sha256, name: $0.sources.first.map { ServerUploadPath.lastComponent(of: $0.path) } ?? row.name,
                                                           size: $0.size) },
                                          setKey: setKey, connectionId: connectionId)
            } else {
                try leftOutStore.include(Set(pair.map(\.sha256)), setKey: setKey)
            }
        } catch {
            CommonPhotosScanModel.logger.error("left out not stored: \(error.localizedDescription, privacy: .public)")
        }
        read()
    }
    @ObservationIgnored private var lastRead = ContinuousClock.now - .seconds(10)
    @ObservationIgnored private var pendingRead: Task<Void, Never>?

    init(runId: String, store: CommonPhotosStore) {
        self.runId = runId
        self.store = store
        read()
    }

    private func reshow() {
        let filtered = rows.filter { row in
            switch filter {
            case .all: true
            case .done: isUndo ? row.status == .undone : [.copied, .moved, .undone].contains(row.status)
            case .skipped: row.status == .skipped
            case .failed: row.status == .failed
            }
        }
        // The store reads them in position order: sorted by it, they
        // already are — 14,000 rows twice a second is not sorted again.
        shown = sortOrder == [KeyPathComparator(\Row.id)] ? filtered : filtered.sorted(using: sortOrder)
    }

    private static func counts(_ rows: [Row], isUndo: Bool) -> Counts {
        rows.reduce(into: Counts()) { counts, row in
            if row.datesLost { counts.datesLost += 1 }
            switch row.status {
            case .copied, .moved: counts.done += 1
            // A gathering run's undone photos were copied or moved first,
            // as Activity counts them.
            case .undone: counts.done += 1; if !isUndo { counts.undone += 1 }
            case .skipped: counts.skipped += 1
            case .failed: counts.failed += 1
            default: break
            }
        }
    }

    /// The run moved: read again, at most twice a second.
    func runChanged() {
        guard pendingRead == nil else { return }
        let wait = max(.zero, .milliseconds(500) - (ContinuousClock.now - lastRead))
        pendingRead = Task { [weak self] in
            try? await Task.sleep(for: wait)
            await self?.readNow()
            self?.pendingRead = nil
        }
    }

    func read() {
        Task { await readNow() }
    }

    func readNow() async {
        lastRead = .now
        // Reads finish out of order: only the latest one lands.
        readGeneration += 1
        let generation = readGeneration
        let store = store
        let runId = runId
        let read: (CommonPhotosRun, [CommonPhotosItem], [Row], Set<String>, [CommonPhotosItem])? = await Task.detached(priority: .userInitiated) {
            guard let run = (try? store.run(id: runId)) ?? nil else { return nil }
            let items = (try? store.items(runId: runId)) ?? []
            let setKey = CommonPhotosIncremental.setKey(connectionId: run.connectionId, folders: run.folders, destination: run.destination)
            let leftOut = run.state == .ready
                ? Set(((try? CommonPhotosLeftOutStore(database: store.database).entries(setKey: setKey)) ?? []).map(\.sha256)) : []
            return (run, items, items.map { Self.row($0, run: run, leftOut: leftOut) }, leftOut,
                    CommonPhotosInfoRestorer.candidates(items, run: run))
        }.value
        guard let (run, items, rows, leftOut, restorable) = read, generation == readGeneration else { return }
        self.leftOut = leftOut
        setKey = CommonPhotosIncremental.setKey(connectionId: run.connectionId, folders: run.folders, destination: run.destination)
        connectionId = run.connectionId
        csvName = run.csvPath.map { ServerUploadPath.lastComponent(of: $0) }
        runUpdatedAt = run.updatedAt
        isUndo = run.isUndo
        self.items = items
        restorableLost = restorable.count(where: { $0.fileInfo == .datesNotKept })
        restorableUnknown = restorable.count(where: { $0.fileInfo == nil })
        if rows != self.rows { self.rows = rows }
    }

    /// ⌘C: the picked rows under a header, as the CSV has them — its
    /// status words and reasons, every path whole — tab-separated.
    func copyText() -> String {
        let picked = shown.filter { selection.contains($0.id) }
        guard !picked.isEmpty else { return "" }
        func field(_ text: String) -> String {
            text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        let header = ["Status", "Name", "From", "To", "SHA-256", "Reason", "File info", "Check"].joined(separator: "\t")
        return ([header] + picked.map { row in
            [row.csvStatus, row.name, row.fromPaths, row.toPath, row.sha256, row.csvReason, row.csvFileInfo, row.csvCheck].map(field).joined(separator: "\t")
        }).joined(separator: "\n")
    }

    nonisolated private static func row(_ item: CommonPhotosItem, run: CommonPhotosRun, leftOut: Set<String> = []) -> Row {
        let name = item.sources.first.map { ServerUploadPath.lastComponent(of: $0.path) } ?? ""
        var status = CommonPhotosLog.status(item.status)
        if run.isUndo, item.status == .failed {
            status = String(localized: "Not undone", comment: "Common photos undo log status: the photo was not taken back")
        } else if run.isUndo, [.copying, .moving, .placed].contains(item.status) {
            status = String(localized: "Undoing…", comment: "Common photos undo log status: the photo being taken back")
        } else if run.state == .ready, item.status == .pending, leftOut.contains(item.sha256) {
            // §6d: unchecked — stored for the set, Move leaves it.
            status = String(localized: "Left out from now on", comment: "Common photos log status: a photo the user left out of a ready run")
        } else if run.state == .ready, item.status == .pending {
            status = String(localized: "Ready to move", comment: "Common photos log status: found by Keep gathering, not moved yet")
        } else if item.status == .skipped, item.failure?.0 == .alreadyThere {
            status = String(localized: "Skipped (already there)", comment: "Common photos log status: same bytes in the destination")
        }
        // Restore File Info… left it alone (changed in Shared, no first copy).
        let notRestored = item.fileInfo != .kept && (item.failure?.reason).map { CommonPhotosInfoRestorer.ownReasons.contains($0) } == true
        return Row(id: item.position, status: item.status, statusText: status, name: name,
                   from: item.sources.map { place($0.path, run: run, name: name) }.joined(separator: " · "),
                   to: item.destinationPath.map { landing($0, run: run) } ?? "",
                   shortSHA: (item.isDone || run.state == .ready) && item.sha256.count > 8 && !item.sha256.hasPrefix(CommonPhoto.quickPrefix)
                       ? "\(item.sha256.prefix(4))…\(item.sha256.suffix(4))" : "—",
                   reason: CommonPhotosLog.reason(item),
                   check: run.isUndo || item.status == .skipped ? "" : CommonPhotosLog.check(item.checkMethod),
                   fileInfo: run.state == .ready ? "" : notRestored ? String(localized: "Not restored", comment: "Common photos log, File info column: Restore File Info left this copy alone (the Reason says why)")
                       : CommonPhotosLog.fileInfo(item.fileInfo),
                   datesLost: item.fileInfo == .datesNotKept || notRestored,
                   csvStatus: run.isUndo && item.status == .failed ? "Not undone" : CommonPhotosLog.csvStatus(item.status),
                   csvReason: CommonPhotosLog.csvReason(item),
                   csvFileInfo: item.fileInfo?.rawValue ?? "",
                   csvCheck: run.isUndo || item.status == .skipped ? "" : item.checkMethod?.rawValue ?? "",
                   fromPaths: item.sources.map(\.path).joined(separator: "; "), toPath: item.destinationPath ?? "",
                   sha256: item.sha256.hasPrefix(CommonPhoto.quickPrefix) ? "" : item.sha256)
    }

    /// "Shared/2025/10/12/DSC04388.ARW": where the copy is under the
    /// destination, its dated or kept folders included (FS-19.08 §6e).
    nonisolated static func landing(_ path: String, run: CommonPhotosRun) -> String {
        let root = ServerUploadPath.normalizedFolder(run.destination)
        let full = ServerUploadPath.normalizedFolder(path)
        let name = ServerUploadPath.lastComponent(of: run.destination)
        guard full.hasPrefix(root + "/") else { return ServerUploadPath.join(name, ServerUploadPath.lastComponent(of: path)) }
        return ServerUploadPath.join(name, String(full.dropFirst(root.count + 1)))
    }

    /// "Tuấn/Da Lat", or "Vợ/Phone/2025-06-01 IMG_4021.HEIC" when the name
    /// differs from the first copy's.
    nonisolated private static func place(_ path: String, run: CommonPhotosRun, name: String) -> String {
        guard let folder = run.folders.first(where: { CommonPhotosSelection.contains($0, path) }) else { return path }
        let root = ServerUploadPath.normalizedFolder(folder)
        let full = ServerUploadPath.normalizedFolder(path)
        let relative = full.hasPrefix(root) ? String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : full
        let fileName = ServerUploadPath.lastComponent(of: relative)
        let shown = fileName.lowercased() == name.lowercased() ? ServerUploadPath.parent(of: relative) : relative
        return ServerUploadPath.join(ServerUploadPath.lastComponent(of: folder), shown)
    }
}

private struct MacCommonPhotosRunContent: View {
    let entry: MacCommonPhotosRuns.Entry
    @Bindable var log: MacCommonPhotosLogModel
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsStop = false
    /// Move N… on a ready run (FS-19.08 §6c): asked before anything moves.
    @State private var confirmsMove = false
    /// Undo Copy… / Undo Move… or Undo Selected… asked (FS-19.08 §6b): the
    /// rows chosen, nil for the whole run.
    @State private var undoing: Set<Int>??
    @State private var undoProblem: String?
    /// Restore File Info… asked (FS-19.08 §6e): the rows chosen, nil for
    /// every copy that needs it.
    @State private var restoring: Set<Int>??
    /// How many copies the Restore question is about, fixed when it is asked.
    @State private var restoreCount = 0
    /// Whether Undo is offered, read from the store when the run's state or
    /// its rows change — never per frame.
    @State private var canUndo = false

    private var runs: MacCommonPhotosRuns { dependencies.commonPhotos }
    private var run: CommonPhotosRun { entry.run }
    private var progress: CommonPhotosRunner.Progress { entry.progress }
    private var destinationName: String { ServerUploadPath.lastComponent(of: run.destination) }
    private var restore: MacCommonPhotosRuns.Restore? { runs.restores[run.id] }
    /// The copies Restore File Info… would set (§6e) — the selection's,
    /// scanned when the menu or the question asks.
    private func restorable(_ positions: Set<Int>) -> [CommonPhotosItem] {
        CommonPhotosInfoRestorer.candidates(log.items, run: run, positions: positions)
    }
    private var restorableCount: Int { log.restorableLost + log.restorableUnknown }

    private func askRestore(_ positions: Set<Int>?) {
        restoreCount = positions.map { restorable($0).count } ?? restorableCount
        restoring = .some(positions)
    }
    private var firstFolderName: String { run.folders.first.map(ServerUploadPath.lastComponent(of:)) ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
            filterBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            MacCommonPhotosLogTable(log: log, run: run, isReady: entry.isReady, isRunning: entry.isRunning,
                                    isFinished: entry.isFinished, canUndo: canUndo, isRestoring: restore?.isRunning == true,
                                    undo: { undoing = .some($0) }, restore: { askRestore($0) })
                .equatable()
                .padding(.horizontal, 16)
            footer
                .padding(.horizontal, 16)
                .frame(height: 52)
        }
        .navigationTitle(title)
        .onChange(of: entry.progress.doneCount) { _, done in
            log.runChanged()
            #if DEBUG
            // `-ShotDexCommonPhotosAskStop`: the Stop question after two photos, for a screenshot.
            if done == 2, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosAskStop") { confirmsStop = true }
            #endif
        }
        .onChange(of: entry.progress.currentName) { log.runChanged() }
        // Move N… in Activity opened this window to ask.
        .task(id: runs.moveAsked) {
            guard runs.moveAsked == run.id else { return }
            runs.moveAsked = nil
            await log.readNow()
            if entry.isReady, readyCount > 0 { confirmsMove = true }
        }
        .alert(moveTitle, isPresented: $confirmsMove) {
            Button(String(localized: "Move", comment: "Mac common photos: confirm the move"), role: .destructive) {
                // Refused: it stays ready, and the header says why.
                // What the alert counted: a choice made elsewhere since asks again.
                let moving = Set(log.items.filter { $0.status == .pending && !log.leftOut.contains($0.sha256) }.map(\.sha256))
                guard runs.moveReady(runId: run.id, asOf: log.runUpdatedAt, moving: moving) == .listChanged else { return }
                // A pass changed the list meanwhile: show it and ask again.
                Task {
                    await log.readNow()
                    if entry.isReady, readyCount > 0 { confirmsMove = true }
                }
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            let leftOutCount = log.items.filter { $0.status == .pending }.count - readyCount
            Text(MacCommonPhotosWords.moveMessage(folders: run.folders, destination: destinationName)
                 + (leftOutCount > 0 ? " " + String(localized: "\(leftOutCount.formatted()) left out stay where they are.",
                                                    comment: "Common photos: Move confirmation, photos left out of the ready list") : ""))
        }
        .onChange(of: entry.state) { log.read() }
        .onChange(of: entry.isRunning) { log.read() }
        // An undo of this run started or ended: its rows changed under it.
        .onChange(of: runs.generation) { log.read() }
        .task(id: "\(entry.state.rawValue)-\(entry.isRunning)-\(log.rows.count)-\(log.undoneCount)-\(runs.generation)") { refreshCanUndo() }
        #if DEBUG
        // `-ShotDexCommonPhotosReadyLeaveOut IMG_0002.JPG`: that ready row unchecked (§6d), for screenshots.
        .task(id: "\(entry.isReady)-\(log.rows.count)") {
            let arguments = ProcessInfo.processInfo.arguments
            guard entry.isReady, let index = arguments.firstIndex(of: "-ShotDexCommonPhotosReadyLeaveOut"), index + 1 < arguments.count,
                  let row = log.rows.first(where: { $0.name.hasSuffix(arguments[index + 1]) }), !log.leftOut.contains(row.sha256) else { return }
            log.setLeftOut(true, row: row)
        }
        // `-ShotDexCommonPhotosAskUndo`: the Undo question once the run is done;
        // `-ShotDexCommonPhotosUndoAfterRun`: undo it at once, for screenshots.
        .task(id: "\(entry.state.rawValue)-\(log.rows.count)") {
            guard entry.isFinished, !run.isUndo, !log.rows.isEmpty, runs.canUndo(runId: run.id) else { return }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-ShotDexCommonPhotosAskUndo") { undoing = .some(nil) }
            if arguments.contains("-ShotDexCommonPhotosUndoAfterRun"), canUndo { startUndo(nil) }
            // `-ShotDexCommonPhotosRestoreAfterRun`: Restore File Info… at once (§6e), for screenshots.
            if arguments.contains("-ShotDexCommonPhotosRestoreAfterRun"), restore == nil, restorableCount > 0 {
                runs.restoreFileInfo(runId: run.id)
            }
        }
        #endif
        // Rows Restore File Info… sets show as they land, twice a second at most.
        .onChange(of: restore?.progress.done) { log.runChanged() }
        .onChange(of: restore?.isRunning) { log.read() }
        .alert(restoreTitle, isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button(String(localized: "Restore", comment: "Common photos: confirm Restore File Info")) {
                if let chosen = restoring { runs.restoreFileInfo(runId: run.id, positions: chosen) }
                restoring = nil
            }
            Button(String(localized: "Cancel", comment: "Common photos: cancel Restore File Info"), role: .cancel) { restoring = nil }
        } message: {
            Text(String(localized: "Each copy in “\(destinationName)” gets the modified date and read-only mark of the same photo in \(firstFolderName), the first folder. Nothing is copied again; a copy changed since is left as it is.",
                        comment: "Common photos: what Restore File Info does"))
        }
        .alert(undoTitle, isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } })) {
            Button(run.action == .move ? String(localized: "Undo Move", comment: "Common photos: confirm undoing a Move")
                                       : String(localized: "Undo Copy", comment: "Common photos: confirm undoing a Copy")) {
                if let chosen = undoing { startUndo(chosen) }
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(undoMessage)
        }
        .alert(String(localized: "Couldn’t Start the Undo", comment: "Common photos: the undo could not start"),
               isPresented: Binding(get: { undoProblem != nil }, set: { if !$0 { undoProblem = nil } })) {
            Button(String(localized: "OK", comment: "Mac alert: dismiss")) {}
        } message: {
            Text(undoProblem ?? "")
        }
        .confirmationDialog(run.isUndo ? String(localized: "Stop undoing?", comment: "Common photos: confirm Stop of an undo")
                            : run.action == .move ? String(localized: "Stop moving?", comment: "Common photos: confirm Stop of a Move")
                                                  : String(localized: "Stop copying?", comment: "Common photos: confirm Stop of a Copy"),
                            isPresented: $confirmsStop) {
            Button(String(localized: "Stop", comment: "Common photos: end the run for good"), role: .destructive) {
                runs.stop(runId: run.id)
            }
            Button(String(localized: "Keep Going", comment: "Common photos: do not stop the run"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(run.action == .move || run.isUndo
                 ? MacCommonPhotosWords.whatIsDone(log.items, run: run) + " " + String(localized: "You can't resume this run.", comment: "Common photos: Stop is permanent")
                 : String(localized: "Photos already copied stay where they are. The rest won't be copied, and you can't resume this run.",
                          comment: "Common photos: what Stop does to a Copy"))
        }
    }

    /// "Common Photos — Tuấn + Vợ → Shared"; "Undo — Shared → Tuấn + Vợ".
    private var title: String {
        let folders = run.folders.map { ServerUploadPath.lastComponent(of: $0) }.joined(separator: " + ")
        var title = run.isUndo
            ? String(localized: "Undo — \(destinationName) → \(folders)", comment: "Common photos window title: an undo run")
            : String(localized: "Common Photos — \(folders) → \(destinationName)", comment: "Common photos window title")
        // Keep gathering's runs are named by their day, as in Activity (§6c).
        if let day = run.day.flatMap(CommonPhotosJob.dayDate) {
            title += " · " + day.formatted(.dateTime.month(.abbreviated).day())
        }
        return title
    }

    // MARK: Undo (FS-19.08 §6b)

    /// The rows an undo would take back: the chosen ones, else all.
    private func undoable(_ chosen: Set<Int>?) -> [CommonPhotosItem] {
        // An undo's rows Not undone keep their run's row positions; the
        // store checks those rows are still undoable.
        log.items.filter { (run.isUndo ? $0.status == .failed : $0.isUndoable) && (chosen?.contains($0.position) ?? true) }
    }

    /// The run an undo from this window takes back: this one, or — in an
    /// undo's window, to retry rows not undone — the run it undid.
    private var undoTarget: String { run.undoOf ?? run.id }

    private func refreshCanUndo() {
        canUndo = (entry.isFinished || entry.isStopped) && runs.canUndo(runId: undoTarget)
    }

    private var undoTitle: String {
        let count = undoable(undoing ?? nil).count
        if count == 1 {
            return run.action == .move
                ? String(localized: "Undo moving 1 photo?", comment: "Common photos: confirm undoing a Move of one photo")
                : String(localized: "Undo copying 1 photo?", comment: "Common photos: confirm undoing a Copy of one photo")
        }
        return run.action == .move
            ? String(localized: "Undo moving \(count.formatted()) photos?", comment: "Common photos: confirm undoing a Move")
            : String(localized: "Undo copying \(count.formatted()) photos?", comment: "Common photos: confirm undoing a Copy")
    }

    private var undoMessage: String {
        let folders = ListFormatter.localizedString(byJoining: run.folders.map { ServerUploadPath.lastComponent(of: $0) })
        return run.action == .move
            ? String(localized: "Each photo is put back in \(folders) and checked, then removed from “\(destinationName)”.",
                     comment: "Common photos: what undoing a Move does")
            : String(localized: "The copies in “\(destinationName)” are removed. The photos in \(folders) stay where they are.",
                     comment: "Common photos: what undoing a Copy does")
    }

    private var restoreTitle: String {
        let count = restoreCount
        return count == 1
            ? String(localized: "Restore file info for 1 copy?", comment: "Common photos: Restore File Info question")
            : String(localized: "Restore file info for \(count.formatted()) copies?", comment: "Common photos: Restore File Info question")
    }

    private func startUndo(_ chosen: Set<Int>?) {
        do {
            let undoId = try runs.startUndo(of: undoTarget, positions: chosen)
            openWindow(id: MacCommonPhotosRunWindow.id, value: undoId)
        } catch let refusal as CommonPhotosStore.UndoRefusal {
            undoProblem = switch refusal {
            case .notOver: String(localized: "Only a run that has finished or was stopped can be undone.", comment: "Common photos: undo refused")
            case .undoUnfinished: String(localized: "An undo of this run hasn’t finished. Resume or discard it first.", comment: "Common photos: undo refused")
            case .nothingToUndo: String(localized: "None of these photos was copied or moved by this run.", comment: "Common photos: undo refused")
            }
        } catch {
            undoProblem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        log.read()
        refreshCanUndo()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline).fontWeight(.semibold).monospacedDigit().lineLimit(1)
                    // One line, kept when empty (board): the bar under it
                    // never moves as the line changes.
                    Text(detail ?? " ").font(.subheadline).foregroundStyle(entry.problem != nil ? Color(nsColor: .systemRed) : .secondary)
                        .monospacedDigit().lineLimit(1)
                        .help(detail ?? "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
            .frame(minHeight: 28)
            if !entry.isFinished && !entry.isStopped && !entry.isReady {
                ProgressView(value: entry.fraction)
                    .progressViewStyle(.linear)
                    .tint(MacTheme.accent)
                    .accessibilityLabel(headline)
            }
        }
    }

    private var ofTotal: String {
        String(localized: "\(progress.doneCount.formatted()) of \(progress.totalCount.formatted())", comment: "Common photos window: N of M photos")
    }

    /// The state line (FS-19.08 §7): "Stopped" only for the user's Stop; a
    /// lost connection or a quit is "Interrupted".
    private var headline: String {
        if entry.isFinished { return summary }
        if entry.isReady {
            let waiting = log.items.filter { $0.status == .pending }.count
            let found = waiting == 1
                ? String(localized: "1 photo ready to move", comment: "Common photos window: Keep gathering found one photo for a Move set")
                : String(localized: "\(waiting.formatted()) photos ready to move", comment: "Common photos window: Keep gathering found photos for a Move set")
            // §6d: some left out — how many Move takes.
            guard readyCount < waiting else { return found }
            return found + " · " + String(localized: "\(readyCount.formatted()) checked", comment: "Common photos window: ready photos still checked")
        }
        if entry.isStopped { return String(localized: "Stopped at \(ofTotal)", comment: "Common photos window: the user stopped the run") }
        if entry.isRunning && entry.isFinishing {
            return String(localized: "Writing the log and rescanning…", comment: "Common photos window: the run is finishing")
        }
        if entry.isRunning {
            let position = String(localized: "\(entry.position.formatted()) of \(progress.totalCount.formatted())", comment: "Common photos window: photo N of M")
            let bytes = String(localized: "\(progress.doneBytes.formatted(.byteCount(style: .file))) of \(progress.totalBytes.formatted(.byteCount(style: .file)))",
                               comment: "Common photos window: bytes done of total")
            return run.isUndo
                ? String(localized: "Undoing \(position) · \(bytes)", comment: "Common photos window: running undo")
                : run.action == .move
                ? String(localized: "Moving \(position) · \(bytes)", comment: "Common photos window: running Move")
                : String(localized: "Copying \(position) · \(bytes)", comment: "Common photos window: running Copy")
        }
        if entry.isPausedByUser { return String(localized: "Paused at \(ofTotal)", comment: "Common photos window: the run is paused") }
        return String(localized: "Interrupted at \(ofTotal)", comment: "Common photos window: the run stopped on an error or a quit")
    }

    /// The file being worked on and the time left, why it stopped, or what
    /// a Move has removed so far.
    private var detail: String? {
        if entry.isReady, let problem = entry.problem { return problem }
        if entry.isReady {
            return String(localized: "Keep gathering found them. Nothing has been moved yet.", comment: "Common photos window: a ready run")
        }
        if entry.isRunning && entry.isFinishing {
            return String(localized: "Pause and Stop are off until it finishes.", comment: "Common photos window: finishing")
        }
        if entry.isRunning, let name = progress.currentName, let step = progress.currentStep {
            var line = "\(name) · \(CommonPhotosJob.words(step, destination: destinationName, isUndo: run.isUndo))"
            if let seconds = entry.secondsLeft, seconds >= 1 { line += " · " + Self.timeLeft(seconds) }
            return line
        }
        if let problem = entry.problem {
            let done = run.action == .move
                ? MacCommonPhotosWords.whatIsDone(log.items, run: run)
                : String(localized: "The \(log.counts.done.formatted()) photos done are safe.", comment: "Common photos window: after a connection error")
            return problem + " " + done + " " + String(localized: "Try Again continues from here.", comment: "Common photos window: after a connection error")
        }
        if !entry.isRunning, !entry.isFinished, run.action == .move, !log.items.isEmpty {
            return MacCommonPhotosWords.whatIsDone(log.items, run: run)
        }
        if entry.isInterrupted, !entry.isFinished {
            return String(localized: "The \(log.counts.done.formatted()) photos done are safe. Resume continues from here.",
                          comment: "Common photos window: a run a quit interrupted")
        }
        if !entry.warnings.isEmpty { return entry.warnings.joined(separator: " ") }
        if entry.isFinished, run.isUndo, log.counts.failed > 0 {
            return log.counts.failed == 1
                ? String(localized: "1 not undone — select it and choose Undo Selected… to try again",
                         comment: "Common photos window: how to retry a row an undo left")
                : String(localized: "\(log.counts.failed.formatted()) not undone — select them and choose Undo Selected… to try again",
                         comment: "Common photos window: how to retry rows an undo left")
        }
        if let restore {
            if restore.isStopping {
                return String(localized: "Stopping after this photo…", comment: "Common photos window: Restore File Info stopping")
            }
            if restore.isRunning {
                return String(localized: "Restoring file info · \(restore.progress.done.formatted()) of \(restore.progress.total.formatted())",
                              comment: "Common photos window: Restore File Info is going")
            }
            let progress = restore.progress
            var parts = [progress.restored == 1
                ? String(localized: "File info restored on 1 copy", comment: "Common photos window: what Restore File Info did")
                : String(localized: "File info restored on \(progress.restored.formatted()) copies", comment: "Common photos window: what Restore File Info did")]
            if progress.leftAlone > 0 {
                parts.append(String(localized: "\(progress.leftAlone.formatted()) left as they were", comment: "Common photos window: copies Restore File Info did not touch (changed in Shared, or no first copy)"))
            }
            var line = parts.joined(separator: " · ") + "."
            if progress.refused > 0 {
                line += " " + String(localized: "The server did not accept the dates of \(progress.refused.formatted()).", comment: "Common photos window: Restore File Info on a server that keeps no dates")
            }
            if let problem = restore.problem, progress.done == 0, progress.total == 0 { return problem }
            if let problem = restore.problem {
                return problem + " " + line + " " + String(localized: "Restore File Info… continues from here.", comment: "Common photos window: after Restore File Info stopped on an error")
            }
            return line + " " + (restore.wasStopped
                ? String(localized: "Stopped — Restore File Info… does the rest.", comment: "Common photos window: Restore File Info was stopped")
                : String(localized: "Nothing was copied again.", comment: "Common photos window: Restore File Info copies no bytes"))
        }
        if entry.isFinished, log.restorableLost > 0 {
            return log.restorableLost == 1
                ? String(localized: "1 copy did not keep its dates. Restore File Info… sets them without copying again.",
                         comment: "Common photos window: one copy lost its dates (FS-19.08 §6e)")
                : String(localized: "\(log.restorableLost.formatted()) copies did not keep their dates. Restore File Info… sets them without copying again.",
                         comment: "Common photos window: copies lost their dates (FS-19.08 §6e)")
        }
        if entry.isFinished, log.restorableUnknown > 0 {
            return String(localized: "These copies were made before ShotDex kept file dates. Restore File Info… sets them without copying again.",
                          comment: "Common photos window: a run from before FS-19.08 §6e")
        }
        if canUndo, !run.isUndo {
            return run.action == .move
                ? String(localized: "Undo Move… puts these photos back where they were.", comment: "Common photos window: what Undo does")
                : String(localized: "Undo Copy… takes these copies back out of “\(destinationName)”.", comment: "Common photos window: what Undo does")
        }
        return nil
    }

    static func timeLeft(_ seconds: Double) -> String { CommonPhotosJob.timeLeft(seconds) }

    static func words(_ step: CommonPhotosRunner.Progress.Step, destination: String) -> String {
        CommonPhotosJob.words(step, destination: destination)
    }

    @ViewBuilder
    private var actions: some View {
        let stoppable = runs.canStop(runId: run.id)
        if entry.isFinished || entry.isStopped || entry.isReady {
            EmptyView()
        } else if entry.isRunning {
            Button { runs.pause(runId: run.id) } label: { Label(String(localized: "Pause", comment: "Common photos window"), systemImage: "pause.fill") }
                .disabled(!stoppable)
            Button { confirmsStop = true } label: { Label(String(localized: "Stop", comment: "Common photos window"), systemImage: "stop.fill") }
                .disabled(!stoppable)
        } else {
            Button(entry.problem == nil ? String(localized: "Resume", comment: "Common photos window: run again from where it stopped")
                                        : String(localized: "Try Again", comment: "Common photos window: run again after a connection error")) {
                runs.resume(runId: run.id)
            }
            .disabled(!run.canResume)
            Button { confirmsStop = true } label: { Label(String(localized: "Stop", comment: "Common photos window"), systemImage: "stop.fill") }
                .disabled(!stoppable)
        }
    }

    // MARK: Log

    private var filterBar: some View {
        HStack {
            Picker(selection: $log.filter) {
                Text("All", comment: "Common photos log filter").tag(MacCommonPhotosLogModel.Filter.all)
                if run.isUndo {
                    Text("Undone", comment: "Common photos undo log filter").tag(MacCommonPhotosLogModel.Filter.done)
                    Text("Not undone", comment: "Common photos undo log filter").tag(MacCommonPhotosLogModel.Filter.failed)
                } else {
                    Text(run.action == .move ? String(localized: "Moved", comment: "Common photos log filter")
                                             : String(localized: "Copied", comment: "Common photos log filter"))
                        .tag(MacCommonPhotosLogModel.Filter.done)
                    Text("Skipped", comment: "Common photos log filter").tag(MacCommonPhotosLogModel.Filter.skipped)
                    Text("Failed", comment: "Common photos log filter").tag(MacCommonPhotosLogModel.Filter.failed)
                }
            } label: {
                Text("Status", comment: "Common photos log filter")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
    }

    // MARK: Footer

    /// "280 copied · 12 skipped · 0 failed".
    private var summary: String {
        let counts = log.counts
        if run.isUndo {
            var parts = [String(localized: "\(counts.done.formatted()) undone", comment: "Common photos window: count"),
                         String(localized: "\(counts.failed.formatted()) not undone", comment: "Common photos window: count")]
            // Back, but not as they were (FS-19.08 §6e): said, not a failure.
            if counts.datesLost > 0 {
                parts.append(String(localized: "\(counts.datesLost.formatted()) without original dates",
                                    comment: "Common photos undo window: photos put back on a server that gave them today's date"))
            }
            return parts.joined(separator: " · ")
        }
        let done = run.action == .move
            ? String(localized: "\(counts.done.formatted()) moved", comment: "Common photos window: count")
            : String(localized: "\(counts.done.formatted()) copied", comment: "Common photos window: count")
        var parts = [done,
                     String(localized: "\(counts.skipped.formatted()) skipped", comment: "Common photos window: count"),
                     failedText]
        if counts.undone > 0 {
            parts.append(String(localized: "\(counts.undone.formatted()) undone", comment: "Common photos window: photos an undo took back"))
        }
        return parts.joined(separator: " · ")
    }

    /// The photos a ready run still lists.
    /// What Move N… moves: the waiting photos the user did not leave out.
    private var readyCount: Int { log.items.filter { $0.status == .pending && !log.leftOut.contains($0.sha256) }.count }

    /// "Tuấn and Vợ".
    private var folderList: String {
        ListFormatter.localizedString(byJoining: run.folders.map { ServerUploadPath.lastComponent(of: $0) })
    }

    /// "Move 4 photos to “Shared”?"
    private var moveTitle: String {
        readyCount == 1
            ? String(localized: "Move 1 photo to “\(destinationName)”?", comment: "Mac common photos: Move confirmation title")
            : String(localized: "Move \(readyCount.formatted()) photos to “\(destinationName)”?", comment: "Mac common photos: Move confirmation title")
    }

    private var failedText: String {
        String(localized: "\(log.counts.failed.formatted()) failed", comment: "Common photos window: count")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if let csv = log.csvName, entry.isFinished {
                    Text("Log saved in \(destinationName) as “\(csv)”", comment: "Common photos window: where the CSV is")
                } else if entry.isReady, readyCount < log.items.filter({ $0.status == .pending }).count {
                    Text("Unchecked photos stay out of this set. Check one again to include it.",
                         comment: "Common photos window: a ready run with photos left out")
                } else if entry.isReady {
                    Text(String(localized: "Moving copies each photo to “\(destinationName)”, checks it, then removes it from \(folderList).",
                                comment: "Common photos window: what Move does, on a ready run"))
                } else {
                    Text(summary)
                }
            }
            .font(.callout).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isFinished, run.action == .copy, !run.isUndo {
                if restore?.isRunning == true {
                    Button(restore?.isStopping == true ? String(localized: "Stopping…", comment: "Common photos window: Restore File Info stopping")
                                                       : String(localized: "Stop", comment: "Common photos window: stop Restore File Info")) {
                        runs.stopRestore(runId: run.id)
                    }
                    .disabled(restore?.isStopping == true)
                } else {
                    Button(String(localized: "Restore File Info…", comment: "Common photos window: set the sources' dates on copies that lost them (FS-19.08 §6e)")) {
                        askRestore(nil)
                    }
                    .disabled(restorableCount == 0)
                    .help(restorableCount == 0
                          ? String(localized: "Every copy already has its dates.", comment: "Common photos window: Restore File Info is off")
                          : String(localized: "Sets the dates of the copies in “\(destinationName)” from \(firstFolderName), without copying again.",
                                   comment: "Common photos window: Restore File Info tooltip"))
                }
            }
            if canUndo, !run.isUndo {
                Button(run.action == .move ? String(localized: "Undo Move…", comment: "Common photos window: take a Move back")
                                           : String(localized: "Undo Copy…", comment: "Common photos window: take a Copy back")) {
                    undoing = .some(nil)
                }
            }
            if log.counts.failed > 0, !run.isUndo {
                Text(failedText).font(.callout).monospacedDigit().foregroundStyle(Color(nsColor: .systemRed))
                Button(String(localized: "Show Failed", comment: "Common photos window: filter the log to failures")) { log.filter = .failed }
            }
            Button(String(localized: "Show in Browser", comment: "Common photos window: open the destination folder in the server browser")) {
                runs.browserRequest = (run.connectionId, run.destination)
                MacMainWindow.bringForward()
            }
            .disabled(!entry.isFinished && !entry.isReady)
            .help(entry.isFinished || entry.isReady
                  ? String(localized: "Opens “\(destinationName)”, where the photos and the log are.", comment: "Common photos window: Show in Browser tooltip")
                  : String(localized: "Available when the run finishes.", comment: "Common photos window: Show in Browser is off"))
            if entry.isFinished || entry.isStopped, !run.isUndo {
                Button(String(localized: "Run Again…", comment: "Common photos window: open the sheet on the same folders, checking only new photos")) {
                    runs.runAgain(runId: run.id)
                    MacMainWindow.bringForward(openWindow)
                }
            }
            if entry.isFinished || entry.isStopped {
                Button(String(localized: "Done", comment: "Common photos window: close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if entry.isReady {
                // Not Now leaves them listed; the next pass may add more.
                Button(String(localized: "Not Now", comment: "Common photos window: close a ready run without moving")) { dismiss() }
                Button(String(localized: "Move \(readyCount.formatted())…", comment: "Common photos window: move the photos Keep gathering found, after asking")) {
                    // The list as it is now, before asking about it.
                    Task {
                        await log.readNow()
                        confirmsMove = readyCount > 0
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(readyCount == 0)
            }
        }
    }
}

/// The log's table, apart from the header: the run's progress lands ten
/// times a second, and redrawing 14,000 rows on each tick made the list
/// stutter while scrolled. It redraws when the rows are read again or
/// what it shows changes — never for the progress bar.
private struct MacCommonPhotosLogTable: View, Equatable {
    /// Plain, so the nonisolated `==` can compare it; bound in `body`.
    let log: MacCommonPhotosLogModel
    let run: CommonPhotosRun
    let isReady: Bool
    let isRunning: Bool
    let isFinished: Bool
    let canUndo: Bool
    let isRestoring: Bool
    /// Undo Selected… and Restore File Info… asked, for these rows.
    let undo: (Set<Int>) -> Void
    let restore: (Set<Int>) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.log === rhs.log && lhs.run == rhs.run && lhs.isReady == rhs.isReady && lhs.isRunning == rhs.isRunning
            && lhs.isFinished == rhs.isFinished && lhs.canUndo == rhs.canUndo && lhs.isRestoring == rhs.isRestoring
    }

    var body: some View {
        @Bindable var log = log
        Table(log.shown, selection: $log.selection, sortOrder: $log.sortOrder) {
            TableColumn(String(localized: "Status", comment: "Common photos log column"), value: \.statusText) { row in
                statusCell(row)
            }
            .width(min: 110, ideal: 140)
            TableColumn(String(localized: "Name", comment: "Common photos log column"), value: \.name) { row in
                Text(row.name).lineLimit(1)
            }
            .width(min: 80, ideal: 100)
            TableColumn(String(localized: "From", comment: "Common photos log column"), value: \.from) { row in
                Text(row.from).foregroundStyle(.secondary).lineLimit(1).help(row.fromPaths)
            }
            .width(min: 90, ideal: 120)
            TableColumn(String(localized: "To", comment: "Common photos log column"), value: \.to) { row in
                Text(row.to).foregroundStyle(.secondary).lineLimit(1).help(row.toPath)
            }
            .width(min: 100, ideal: 170)
            TableColumn(String(localized: "Check", comment: "Common photos log column: how Same was proven, Quick or Full (FS-19.08 §6e)"), value: \.check) { row in
                Text(row.check).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 50, ideal: 64)
            TableColumn(String(localized: "File info", comment: "Common photos log column: whether the copy kept its source's dates (FS-19.08 §6e)"), value: \.fileInfo) { row in
                Text(row.fileInfo).foregroundStyle(row.datesLost ? Color.orange : .secondary).lineLimit(1)
            }
            .width(min: 96, ideal: 110)
            TableColumn(String(localized: "SHA-256", comment: "Common photos log column"), value: \.sha256) { row in
                Text(row.shortSHA).foregroundStyle(.secondary).monospacedDigit().help(row.sha256)
            }
            .width(min: 64, ideal: 84)
            TableColumn(String(localized: "Reason", comment: "Common photos log column"), value: \.reason) { row in
                Text(row.reason).foregroundStyle(row.status == .failed ? Color(nsColor: .systemRed) : .secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 90)
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int.self) { positions in
            if !positions.isEmpty {
                Button(String(localized: "Undo Selected…", comment: "Common photos log: undo the chosen rows")) {
                    undo(positions)
                }
                .disabled(!canUndo || !log.items.contains { (run.isUndo ? $0.status == .failed : $0.isUndoable) && positions.contains($0.position) })
                if isFinished, run.action == .copy, !run.isUndo {
                    Button(String(localized: "Restore File Info…", comment: "Common photos log: restore the chosen rows' dates")) {
                        restore(positions)
                    }
                    .disabled(isRestoring || CommonPhotosInfoRestorer.candidates(log.items, run: run, positions: positions).isEmpty)
                }
            }
        }
        .overlay {
            if log.shown.isEmpty, !log.rows.isEmpty { emptyFilter }
        }
        .onCopyCommand {
            let text = log.copyText()
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
        }
        .accessibilityLabel(String(localized: "Files", comment: "Common photos log table"))
    }

    private var emptyFilter: some View {
        Text(emptyFilterText).foregroundStyle(.secondary)
    }

    private var emptyFilterText: String {
        switch log.filter {
        case .failed: String(localized: "No failed files", comment: "Common photos log: the Failed filter is empty")
        case .skipped: String(localized: "No skipped files", comment: "Common photos log: the Skipped filter is empty")
        case .done: run.action == .move ? String(localized: "No files moved yet", comment: "Common photos log: the Moved filter is empty")
                                        : String(localized: "No files copied yet", comment: "Common photos log: the Copied filter is empty")
        case .all: ""
        }
    }

    @ViewBuilder
    private func statusCell(_ row: MacCommonPhotosLogModel.Row) -> some View {
        let inFlight = [.copying, .moving, .placed].contains(row.status)
        if isReady, row.status == .pending {
            // §6d: a photo waiting to move — checked, or left out of the set.
            let isLeftOut = log.leftOut.contains(row.sha256)
            HStack(spacing: 6) {
                Toggle(isOn: Binding(get: { !isLeftOut }, set: { log.setLeftOut(!$0, row: row) })) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(row.name)
                    .help(String(localized: "Unchecked: left out of this set from now on. Check it again to include it.",
                                 comment: "Common photos log: ready row checkbox tooltip"))
                    .accessibilityValue(isLeftOut
                        ? String(localized: "Left out", comment: "Common photos log: ready row checkbox, VoiceOver value")
                        : String(localized: "Included", comment: "Common photos log: ready row checkbox, VoiceOver value"))
                Text(row.statusText).lineLimit(1).foregroundStyle(.secondary)
            }
        } else if inFlight, !isRunning {
            // Not going: a photo left mid-step is unfinished, not busy.
            Text("Unfinished", comment: "Common photos log status: a photo left mid-step while the run is not going")
                .foregroundStyle(.orange).lineLimit(1)
        } else {
            busyOrDoneCell(row)
        }
    }

    @ViewBuilder
    private func busyOrDoneCell(_ row: MacCommonPhotosLogModel.Row) -> some View {
        HStack(spacing: 6) {
            switch row.status {
            case .copied, .moved: Image(systemName: "checkmark").fontWeight(.bold)
            case .skipped: Image(systemName: "minus.circle")
            case .failed: Image(systemName: "exclamationmark.triangle")
            case .undone: Image(systemName: "arrow.uturn.backward")
            case .copying, .moving, .placed: ProgressView().controlSize(.mini)
            case .pending: EmptyView()
            }
            Text(row.statusText).lineLimit(1)
        }
        .foregroundStyle(row.status == .copied || row.status == .moved || row.status == .undone ? Color.green
                         : row.status == .failed ? Color(nsColor: .systemRed) : .secondary)
    }

}

/// The Library window, remembered so another window can bring it forward.
enum MacMainWindow {
    /// The Library window group's id, to open one when none is left.
    static let id = "library"
    @MainActor static weak var window: NSWindow?

    @MainActor static func bringForward() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Brings the Library window forward, opening one when it was closed —
    /// so a request it routes (Run Again) is not left waiting.
    @MainActor static func bringForward(_ openWindow: OpenWindowAction) {
        if let window { window.makeKeyAndOrderFront(nil) } else { openWindow(id: id) }
    }
}

/// Records the window it sits in as the Library window.
struct MacMainWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MarkerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MacMainWindow.window = window }
        }
    }
}
