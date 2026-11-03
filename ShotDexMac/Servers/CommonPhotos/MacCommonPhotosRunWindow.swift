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
    static let size = CGSize(width: 900, height: 560)

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
        .frame(minWidth: 720, idealWidth: Self.size.width, minHeight: 420, idealHeight: Self.size.height)
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
        // As the CSV writes them, for ⌘C.
        let csvStatus: String
        let csvReason: String
        let fromPaths: String
        let toPath: String
        let sha256: String
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, done, skipped, failed
        var id: Self { self }
    }

    struct Counts: Equatable {
        var done = 0, skipped = 0, failed = 0
    }

    let runId: String
    private(set) var rows: [Row] = [] {
        didSet { counts = Self.counts(rows); reshow() }
    }
    private(set) var shown: [Row] = []
    private(set) var counts = Counts()
    /// The store's items as last read — the Move wording counts them.
    private(set) var items: [CommonPhotosItem] = []
    var filter = Filter.all { didSet { reshow() } }
    var sortOrder = [KeyPathComparator(\Row.id)] { didSet { reshow() } }
    var selection: Set<Int> = []
    /// The CSV the run left in the destination, once written.
    private(set) var csvName: String?

    @ObservationIgnored private let store: CommonPhotosStore
    @ObservationIgnored private var lastRead = ContinuousClock.now - .seconds(10)
    @ObservationIgnored private var pendingRead: Task<Void, Never>?

    init(runId: String, store: CommonPhotosStore) {
        self.runId = runId
        self.store = store
        read()
    }

    private func reshow() {
        shown = rows.filter { row in
            switch filter {
            case .all: true
            case .done: row.status == .copied || row.status == .moved
            case .skipped: row.status == .skipped
            case .failed: row.status == .failed
            }
        }.sorted(using: sortOrder)
    }

    private static func counts(_ rows: [Row]) -> Counts {
        rows.reduce(into: Counts()) { counts, row in
            switch row.status {
            case .copied, .moved: counts.done += 1
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

    private func readNow() async {
        lastRead = .now
        let store = store
        let runId = runId
        let read: (CommonPhotosRun, [CommonPhotosItem], [Row])? = await Task.detached(priority: .userInitiated) {
            guard let run = (try? store.run(id: runId)) ?? nil else { return nil }
            let items = (try? store.items(runId: runId)) ?? []
            return (run, items, items.map { Self.row($0, run: run) })
        }.value
        guard let (run, items, rows) = read else { return }
        csvName = run.csvPath.map { ServerUploadPath.lastComponent(of: $0) }
        self.items = items
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
        let header = ["Status", "Name", "From", "To", "SHA-256", "Reason"].joined(separator: "\t")
        return ([header] + picked.map { row in
            [row.csvStatus, row.name, row.fromPaths, row.toPath, row.sha256, row.csvReason].map(field).joined(separator: "\t")
        }).joined(separator: "\n")
    }

    nonisolated private static func row(_ item: CommonPhotosItem, run: CommonPhotosRun) -> Row {
        let name = item.sources.first.map { ServerUploadPath.lastComponent(of: $0.path) } ?? ""
        var status = CommonPhotosLog.status(item.status)
        if item.status == .skipped, item.failure?.0 == .alreadyThere {
            status = String(localized: "Skipped (already there)", comment: "Common photos log status: same bytes in the destination")
        }
        return Row(id: item.position, status: item.status, statusText: status, name: name,
                   from: item.sources.map { place($0.path, run: run, name: name) }.joined(separator: " · "),
                   to: item.destinationPath.map { ServerUploadPath.join(ServerUploadPath.lastComponent(of: run.destination), ServerUploadPath.lastComponent(of: $0)) } ?? "",
                   shortSHA: item.isDone && item.sha256.count > 8 ? "\(item.sha256.prefix(4))…\(item.sha256.suffix(4))" : "—",
                   reason: CommonPhotosLog.reason(item),
                   csvStatus: CommonPhotosLog.csvStatus(item.status), csvReason: CommonPhotosLog.csvReason(item),
                   fromPaths: item.sources.map(\.path).joined(separator: "; "), toPath: item.destinationPath ?? "",
                   sha256: item.sha256)
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
    @State private var confirmsStop = false

    private var runs: MacCommonPhotosRuns { dependencies.commonPhotos }
    private var run: CommonPhotosRun { entry.run }
    private var progress: CommonPhotosRunner.Progress { entry.progress }
    private var destinationName: String { ServerUploadPath.lastComponent(of: run.destination) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
            filterBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            table
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
        .onChange(of: entry.state) { log.read() }
        .onChange(of: entry.isRunning) { log.read() }
        .confirmationDialog(run.action == .move ? String(localized: "Stop moving?", comment: "Common photos: confirm Stop of a Move")
                                                : String(localized: "Stop copying?", comment: "Common photos: confirm Stop of a Copy"),
                            isPresented: $confirmsStop) {
            Button(String(localized: "Stop", comment: "Common photos: end the run for good"), role: .destructive) {
                runs.stop(runId: run.id)
            }
            Button(String(localized: "Keep Going", comment: "Common photos: do not stop the run"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(run.action == .move
                 ? MacCommonPhotosWords.whatIsDone(log.items, run: run) + " " + String(localized: "You can't resume this run.", comment: "Common photos: Stop is permanent")
                 : String(localized: "Photos already copied stay where they are. The rest won't be copied, and you can't resume this run.",
                          comment: "Common photos: what Stop does to a Copy"))
        }
    }

    /// "Common Photos — Tuấn + Vợ → Shared".
    private var title: String {
        let folders = run.folders.map { ServerUploadPath.lastComponent(of: $0) }.joined(separator: " + ")
        return String(localized: "Common Photos — \(folders) → \(destinationName)", comment: "Common photos window title")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline).fontWeight(.semibold).monospacedDigit().lineLimit(1)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(entry.problem != nil ? Color(nsColor: .systemRed) : .secondary)
                            .monospacedDigit().lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
            .frame(minHeight: 28)
            if !entry.isFinished && !entry.isStopped {
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
        if entry.isStopped { return String(localized: "Stopped at \(ofTotal)", comment: "Common photos window: the user stopped the run") }
        if entry.isRunning && entry.isFinishing {
            return String(localized: "Writing the log and rescanning…", comment: "Common photos window: the run is finishing")
        }
        if entry.isRunning {
            let position = String(localized: "\(entry.position.formatted()) of \(progress.totalCount.formatted())", comment: "Common photos window: photo N of M")
            let bytes = String(localized: "\(progress.doneBytes.formatted(.byteCount(style: .file))) of \(progress.totalBytes.formatted(.byteCount(style: .file)))",
                               comment: "Common photos window: bytes done of total")
            return run.action == .move
                ? String(localized: "Moving \(position) · \(bytes)", comment: "Common photos window: running Move")
                : String(localized: "Copying \(position) · \(bytes)", comment: "Common photos window: running Copy")
        }
        if entry.isPausedByUser { return String(localized: "Paused at \(ofTotal)", comment: "Common photos window: the run is paused") }
        return String(localized: "Interrupted at \(ofTotal)", comment: "Common photos window: the run stopped on an error or a quit")
    }

    /// The file being worked on and the time left, why it stopped, or what
    /// a Move has removed so far.
    private var detail: String? {
        if entry.isRunning && entry.isFinishing {
            return String(localized: "Pause and Stop are off until it finishes.", comment: "Common photos window: finishing")
        }
        if entry.isRunning, let name = progress.currentName, let step = progress.currentStep {
            var line = "\(name) · \(Self.words(step, destination: destinationName))"
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
        return nil
    }

    static func timeLeft(_ seconds: Double) -> String { CommonPhotosJob.timeLeft(seconds) }

    static func words(_ step: CommonPhotosRunner.Progress.Step, destination: String) -> String {
        CommonPhotosJob.words(step, destination: destination)
    }

    @ViewBuilder
    private var actions: some View {
        let stoppable = runs.canStop(runId: run.id)
        if entry.isFinished || entry.isStopped {
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
                Text(run.action == .move ? String(localized: "Moved", comment: "Common photos log filter")
                                         : String(localized: "Copied", comment: "Common photos log filter"))
                    .tag(MacCommonPhotosLogModel.Filter.done)
                Text("Skipped", comment: "Common photos log filter").tag(MacCommonPhotosLogModel.Filter.skipped)
                Text("Failed", comment: "Common photos log filter").tag(MacCommonPhotosLogModel.Filter.failed)
            } label: {
                Text("Status", comment: "Common photos log filter")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
    }

    private var table: some View {
        Table(log.shown, selection: $log.selection, sortOrder: $log.sortOrder) {
            TableColumn(String(localized: "Status", comment: "Common photos log column"), value: \.statusText) { row in
                statusCell(row)
            }
            .width(min: 110, ideal: 150)
            TableColumn(String(localized: "Name", comment: "Common photos log column"), value: \.name) { row in
                Text(row.name).lineLimit(1)
            }
            .width(min: 80, ideal: 110)
            TableColumn(String(localized: "From", comment: "Common photos log column"), value: \.from) { row in
                Text(row.from).foregroundStyle(.secondary).lineLimit(1).help(row.fromPaths)
            }
            .width(min: 100, ideal: 160)
            TableColumn(String(localized: "To", comment: "Common photos log column"), value: \.to) { row in
                Text(row.to).foregroundStyle(.secondary).lineLimit(1).help(row.toPath)
            }
            .width(min: 100, ideal: 160)
            TableColumn(String(localized: "SHA-256", comment: "Common photos log column"), value: \.sha256) { row in
                Text(row.shortSHA).foregroundStyle(.secondary).monospacedDigit().help(row.sha256)
            }
            .width(min: 60, ideal: 76)
            TableColumn(String(localized: "Reason", comment: "Common photos log column"), value: \.reason) { row in
                Text(row.reason).foregroundStyle(row.status == .failed ? Color(nsColor: .systemRed) : .secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 90)
        }
        .alternatingRowBackgrounds()
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
        if inFlight, !entry.isRunning {
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
        .foregroundStyle(row.status == .copied || row.status == .moved ? Color.green
                         : row.status == .failed ? Color(nsColor: .systemRed) : .secondary)
    }

    // MARK: Footer

    /// "280 copied · 12 skipped · 0 failed".
    private var summary: String {
        let counts = log.counts
        let done = run.action == .move
            ? String(localized: "\(counts.done.formatted()) moved", comment: "Common photos window: count")
            : String(localized: "\(counts.done.formatted()) copied", comment: "Common photos window: count")
        return [done,
                String(localized: "\(counts.skipped.formatted()) skipped", comment: "Common photos window: count"),
                failedText].joined(separator: " · ")
    }

    private var failedText: String {
        String(localized: "\(log.counts.failed.formatted()) failed", comment: "Common photos window: count")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if let csv = log.csvName, entry.isFinished {
                    Text("Log saved in \(destinationName) as “\(csv)”", comment: "Common photos window: where the CSV is")
                } else {
                    Text(summary)
                }
            }
            .font(.callout).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if log.counts.failed > 0 {
                Text(failedText).font(.callout).monospacedDigit().foregroundStyle(Color(nsColor: .systemRed))
                Button(String(localized: "Show Failed", comment: "Common photos window: filter the log to failures")) { log.filter = .failed }
            }
            Button(String(localized: "Show in Browser", comment: "Common photos window: open the destination folder in the server browser")) {
                runs.browserRequest = (run.connectionId, run.destination)
                MacMainWindow.bringForward()
            }
            .disabled(!entry.isFinished)
            .help(entry.isFinished
                  ? String(localized: "Opens “\(destinationName)”, where the photos and the log are.", comment: "Common photos window: Show in Browser tooltip")
                  : String(localized: "Available when the run finishes.", comment: "Common photos window: Show in Browser is off"))
            if entry.isFinished || entry.isStopped {
                Button(String(localized: "Done", comment: "Common photos window: close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The Library window, remembered so another window can bring it forward.
enum MacMainWindow {
    @MainActor static weak var window: NSWindow?

    @MainActor static func bringForward() {
        window?.makeKeyAndOrderFront(nil)
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
