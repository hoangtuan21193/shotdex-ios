import SwiftUI

/// Window › Activity ⌥⌘0 (board `MAC_Activity`, FS-18.01 §4): every
/// long-running job as one row — going first, then waiting, then over —
/// with its own controls. Its own window, never a sheet; closing it stops
/// nothing. Common-photos runs are its first producer (FS-19.08 §7).
struct MacActivityWindow: View {
    static let id = "activity"
    /// Board `MAC_Activity`: 900×560.
    static let size = CGSize(width: 900, height: 560)

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow
    /// What the store says of each listed run, read off the main actor when
    /// runs start or end — not on every progress tick.
    @State private var stored: [String: Stored] = [:]
    @State private var stopping: LongRunningJob?
    /// The Stop question's words, worked out once when it opens.
    @State private var stopText = (title: "", message: "")
    /// Remove from List… / Remove Finished from List… asked: these runs.
    @State private var removing: [String] = []
    /// Keep gathering's sets (FS-19.08 §6c), read with the runs.
    @State private var watchRows: [CommonPhotosWatchRow] = []
    /// Stop Gathering asked for this set.
    @State private var stoppingWatch: CommonPhotosWatchRow?

    struct Stored: Sendable {
        var run: CommonPhotosRun
        var progress: CommonPhotosRunner.Progress
        var done = 0, skipped = 0, failed = 0, undone = 0
    }

    private var runs: MacCommonPhotosRuns { dependencies.commonPhotos }

    var body: some View {
        Group {
            if jobs.isEmpty && watchRows.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !watchRows.isEmpty { gathering }
                    if !jobs.isEmpty {
                        list
                        foot
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 640, idealWidth: Self.size.width, minHeight: 360, idealHeight: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(MacTheme.accent)
        .navigationTitle(String(localized: "Activity", comment: "Mac window: long-running jobs"))
        .task(id: runs.generation) { await readStore() }
        // "checked 3 min ago" and what the helper did meanwhile.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await readStore()
            }
        }
        .confirmationDialog(String(localized: "Stop gathering “\(stoppingWatch?.title ?? "")”?", comment: "Mac Activity: confirm Stop Gathering"),
                            isPresented: Binding(get: { stoppingWatch != nil }, set: { if !$0 { stoppingWatch = nil } })) {
            Button(String(localized: "Stop Gathering", comment: "Mac Activity: Keep gathering stops for the set")) {
                if let row = stoppingWatch { stopGathering(row) }
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("No more photos are gathered for these folders. Runs, logs and files stay as they are.",
                 comment: "Mac Activity: what Stop Gathering does")
        }
        .confirmationDialog(stopText.title, isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } })) {
            Button(String(localized: "Stop", comment: "Common photos: end the run for good"), role: .destructive) {
                if let job = stopping { runs.stop(runId: job.id) }
            }
            Button(String(localized: "Keep Going", comment: "Common photos: do not stop the run"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(stopText.message)
        }
        .alert(removeTitle, isPresented: Binding(get: { !removing.isEmpty }, set: { if !$0 { removing = [] } })) {
            Button(String(localized: "Remove", comment: "Mac Activity: remove finished runs from the list")) {
                runs.remove(runIds: removing)
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            if removesReady {
                Text("Nothing was moved. While Keep gathering is on, its next check lists these photos again.",
                     comment: "Mac Activity: what Remove from List does to photos ready to move")
            } else {
                Text("Their logs are removed, so you can’t undo these runs afterwards. Nothing on the server changes.",
                     comment: "Mac Activity: what Remove from List costs")
            }
        }
    }

    /// Remove from List on a row ready to move (§6c): its photos go, unmoved.
    private var removesReady: Bool {
        removing.count == 1 && jobs.first { $0.id == removing[0] }?.state == .readyToMove
    }

    private var removeTitle: String {
        removing.count == 1
            ? String(localized: "Remove this run from the list?", comment: "Mac Activity: confirm Remove from List")
            : String(localized: "Remove \(removing.count.formatted()) finished runs from the list?", comment: "Mac Activity: confirm Remove Finished from List")
    }

    // MARK: Jobs

    /// Each run as a row: the live entry where this launch has one, else
    /// what the store says.
    private var jobs: [LongRunningJob] {
        stored.compactMap { id, info -> LongRunningJob? in
            var input: CommonPhotosJob.Input
            if let entry = runs.entries[id] {
                input = CommonPhotosJob.Input(run: entry.run, progress: entry.progress, isRunning: entry.isRunning,
                                              isPausedByUser: entry.isPausedByUser, problem: entry.problem,
                                              secondsLeft: entry.secondsLeft)
                input.run.state = entry.state
            } else {
                input = CommonPhotosJob.Input(run: info.run, progress: info.progress, isRunning: false, isPausedByUser: false, problem: nil)
            }
            input.copiedOrMoved = info.done
            input.skipped = info.skipped
            input.failed = info.failed
            input.undone = info.undone
            input.endedAt = Date(timeIntervalSince1970: TimeInterval(info.run.updatedAt))
            return CommonPhotosJob.job(input)
        }
        .sorted { ($0.rank, stored[$1.id]?.run.createdAt ?? 0) < ($1.rank, stored[$0.id]?.run.createdAt ?? 0) }
    }

    private func readStore() async {
        let known = runs.activityKnownRunIds
        let store = runs.store
        let database = dependencies.database
        let servers = dependencies.fileServers
        let rows = await Task.detached(priority: .userInitiated) { () -> [CommonPhotosWatchRow] in
            let ready = Dictionary(grouping: (try? store.readyRuns()) ?? [], by: { $0.watchId ?? "" })
            return ((try? CommonPhotosWatchStore(database: database).watches()) ?? []).compactMap { watch in
                let name = ((try? servers.fetch(id: watch.connectionId)) ?? nil)?.name ?? ""
                let gathered = watch.isOn && watch.action == .copy
                    ? ((try? store.gathered(connectionId: watch.connectionId, folders: watch.folders, destination: watch.destination))?.photoCount ?? 0)
                    : 0
                // Not left out (§6d): what Move would take.
                let waiting = ready[watch.id].map { runs in runs.reduce(0) { $0 + ((try? store.waitingCount(runId: $1.id)) ?? 0) } } ?? 0
                return CommonPhotosWatchRow.make(watch, connectionName: name, gathered: gathered, readyToMove: waiting)
            }
        }.value
        if !Task.isCancelled { watchRows = rows }
        let read = await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            // Finished runs stay, the last 20 groups (FS-19.08 §6b), so their
            // log opens and they can be undone after a restart.
            let ids = (known + ((try? store.unfinishedRuns()) ?? []).map(\.id) + ((try? store.readyRuns()) ?? []).map(\.id)
                       + ((try? store.keptRuns()) ?? []).map(\.id))
                .filter { seen.insert($0).inserted }
            var out: [String: Stored] = [:]
            for id in ids {
                guard let run = (try? store.run(id: id)) ?? nil else { continue }
                let items = (try? store.items(runId: id)) ?? []
                let done = items.filter(\.isDone)
                out[id] = Stored(run: run,
                                 progress: CommonPhotosRunner.Progress(doneCount: done.count, totalCount: items.count,
                                                                       doneBytes: done.reduce(0) { $0 + $1.size },
                                                                       totalBytes: items.reduce(0) { $0 + $1.size }),
                                 // A gathering run's undone photos were copied or moved first.
                                 done: items.filter { run.isUndo ? $0.status == .undone : [.copied, .moved, .undone].contains($0.status) }.count,
                                 skipped: items.filter { $0.status == .skipped }.count,
                                 failed: items.filter { $0.status == .failed }.count,
                                 undone: run.isUndo ? 0 : items.filter { $0.status == .undone }.count)
            }
            return out
        }.value
        // A newer read (a later generation) has the say.
        guard !Task.isCancelled else { return }
        stored = read
    }

    /// Board `MAC_Activity`, Gathering (FS-19.08 §6c): first in the window.
    private var gathering: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gathering", comment: "Mac Activity: the sets Keep gathering runs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(watchRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    MacGatheringRow(row: row, perform: { perform($0, on: row) })
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Gathering", comment: "Mac Activity: the sets Keep gathering runs"))
        }
    }

    private func perform(_ action: CommonPhotosWatchRow.Action, on row: CommonPhotosWatchRow) {
        switch action {
        case .runNow: dependencies.gatherNow(watchId: row.id)
        case .stopGathering: stoppingWatch = row
        case .remove:
            try? CommonPhotosWatchStore(database: dependencies.database).remove(id: row.id)
            Task { await readStore() }
        }
    }

    private func stopGathering(_ row: CommonPhotosWatchRow) {
        try? CommonPhotosWatchStore(database: dependencies.database).stopGathering(id: row.id)
        dependencies.watchesChanged()
        runs.storeChanged()
        Task { await readStore() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                    if index > 0 { Divider() }
                    MacActivityRow(job: job, perform: { perform($0, on: job) })
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Activity", comment: "Mac Activity: the list of jobs"))
    }

    private var foot: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Closing this window doesn’t stop anything — jobs keep running and show at the foot of the sidebar. A job stopped by quitting ShotDex comes back here with Resume. The last 20 finished runs stay here so you can undo them.",
                 comment: "Mac Activity: what closing the window does")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Remove Finished from List…", comment: "Mac Activity: remove every row that is over, after asking")) {
                removing = jobs.filter(\.isOver).map(\.id).filter { runs.canRemove(runId: $0) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!jobs.contains(where: \.isOver))
        }
        .padding(.horizontal, 2)
    }

    /// Board `MAC_Activity`, tweak `empty`.
    private var empty: some View {
        ContentUnavailableView {
            Label(String(localized: "No Activity", comment: "Mac Activity: nothing running"), systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Indexing, imports, uploads, backups, exports and merges show here while they run.",
                 comment: "Mac Activity: empty state")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func perform(_ action: LongRunningJob.Action, on job: LongRunningJob) {
        switch action {
        case .pause: runs.pause(runId: job.id)
        case .resume, .tryAgain: runs.resume(runId: job.id)
        case .stop:
            stopText = stopWords(job)
            stopping = job
        case .showLog: openWindow(id: MacCommonPhotosRunWindow.id, value: job.id)
        case .runAgain:
            runs.runAgain(runId: job.id)
            MacMainWindow.bringForward(openWindow)
        case .remove: if runs.canRemove(runId: job.id) { removing = [job.id] }
        case .moveReady:
            // The run's window asks before anything moves (FS-19.08 §6c).
            runs.moveAsked = job.id
            openWindow(id: MacCommonPhotosRunWindow.id, value: job.id)
        }
    }

    private func stopWords(_ job: LongRunningJob) -> (title: String, message: String) {
        guard let run = stored[job.id]?.run else { return ("", "") }
        let title = run.action == .move ? String(localized: "Stop moving?", comment: "Common photos: confirm Stop of a Move")
                                        : String(localized: "Stop copying?", comment: "Common photos: confirm Stop of a Copy")
        if run.action == .move, let items = try? runs.store.items(runId: job.id) {
            return (title, MacCommonPhotosWords.whatIsDone(items, run: run) + " "
                    + String(localized: "You can't resume this run.", comment: "Common photos: Stop is permanent"))
        }
        return (title, String(localized: "Photos already copied stay where they are. The rest won't be copied, and you can't resume this run.",
                              comment: "Common photos: what Stop does to a Copy"))
    }
}

/// One job (board `MAC_Activity`): its tile, title and aside, the bar, the
/// status line and the step, its controls on the right.
/// One set in Gathering: icon, folders, what the last pass said, and the
/// ⋯ menu (board `MAC_Activity`).
private struct MacGatheringRow: View {
    let row: CommonPhotosWatchRow
    let perform: (CommonPhotosWatchRow.Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Board: a Copy set in accent; a Move set (it waits for the user)
            // and a stopped one on the plain fill.
            let accent = !row.isStopped && !row.isMove
            Image(systemName: row.isStopped ? "exclamationmark.triangle" : "folder.badge.plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(row.isStopped ? Color.orange : accent ? MacTheme.accent : .secondary)
                .frame(width: 28, height: 28)
                .background(accent ? MacTheme.accentSoft : MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).fontWeight(.semibold).lineLimit(1)
                Text(row.detail).font(.subheadline).monospacedDigit().lineLimit(1)
                    .foregroundStyle(row.isStopped ? Color.orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(row.actions, id: \.self) { action in
                    switch action {
                    case .runNow:
                        Button(String(localized: "Run Now", comment: "Mac Activity, Gathering: a pass for this set now")) { perform(action) }
                    case .stopGathering:
                        Button(String(localized: "Stop Gathering…", comment: "Mac Activity, Gathering: no more passes for this set, after asking")) { perform(action) }
                    case .remove:
                        Button(String(localized: "Remove from List", comment: "Mac Activity, Gathering: a set that stopped by itself leaves the list")) { perform(action) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 16, height: 14)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel(String(localized: "Actions for \(row.title)", comment: "Mac Activity, Gathering: the row's menu"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.title)
    }
}

private struct MacActivityRow: View {
    let job: LongRunningJob
    var perform: (LongRunningJob.Action) -> Void

    /// Board: a 28pt tile, 140pt of controls, rows at least 64 tall.
    private static let tile: CGFloat = 28
    private static let controlsWidth: CGFloat = 140

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tileForeground)
                .frame(width: Self.tile, height: Self.tile)
                .background(tileBackground, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.title).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(job.aside).font(.subheadline).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                if let fraction = job.fraction {
                    bar(fraction)
                }
                Text(job.status)
                    .font(.subheadline).monospacedDigit().lineLimit(1)
                    .foregroundStyle(job.state == .interrupted || job.state == .owesFinish ? Color.orange
                                     : job.state == .doneWithFailures ? Color(nsColor: .systemRed) : .secondary)
                if let detail = job.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(job.actions, id: \.self) { action in button(action) }
            }
            .fixedSize()
            .frame(minWidth: Self.controlsWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(job.title)
    }

    @ViewBuilder
    private func button(_ action: LongRunningJob.Action) -> some View {
        switch action {
        case .pause:
            iconButton("pause.fill", String(localized: "Pause \(job.title)", comment: "Mac Activity: pause a job"), action)
        case .stop:
            iconButton("stop.fill", String(localized: "Stop \(job.title)…", comment: "Mac Activity: stop a job"), action)
        case .resume:
            textButton(String(localized: "Resume", comment: "Mac Activity: run again from where it stopped"), action)
        case .tryAgain:
            textButton(String(localized: "Try Again", comment: "Mac Activity: run again after a connection error"), action)
        case .showLog:
            textButton(String(localized: "Show Log", comment: "Mac Activity: open the run's window"), action)
        case .remove:
            textButton(String(localized: "Remove from List…", comment: "Mac Activity: remove a row that is over, after asking"), action)
        case .runAgain:
            textButton(String(localized: "Run Again…", comment: "Mac Activity: open Find Common Photos on the same folders, checking only new photos"), action)
        case .moveReady(let count):
            textButton(String(localized: "Move \(count.formatted())…", comment: "Mac Activity: move the photos Keep gathering found, after asking"), action)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: LongRunningJob.Action) -> some View {
        Button { perform(action) } label: { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(label)
            .accessibilityLabel(label)
    }

    private func textButton(_ title: String, _ action: LongRunningJob.Action) -> some View {
        // System bordered buttons: the keyboard focus ring comes with them.
        Button(title) { perform(action) }.buttonStyle(.bordered).controlSize(.small)
    }

    /// Board: a 5pt bar, amber while it goes, grey while it waits — drawn,
    /// so it keeps its colour when the window is not the key one.
    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MacTheme.fill)
                Capsule()
                    .fill(job.state == .running || job.state == .finishing ? MacTheme.accent : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel(job.title)
        .accessibilityValue(barValue(fraction))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// "39 percent, interrupted".
    private func barValue(_ fraction: Double) -> String {
        let percent = String(localized: "\(Int((fraction * 100).rounded())) percent", comment: "Mac Activity: progress for VoiceOver")
        let state: String? = switch job.state {
        case .running: nil
        case .finishing: String(localized: "finishing", comment: "Mac Activity: progress state for VoiceOver")
        case .paused: String(localized: "paused", comment: "Mac Activity: progress state for VoiceOver")
        case .readyToMove: String(localized: "ready to move", comment: "Mac Activity: progress state for VoiceOver")
        case .interrupted, .owesFinish: String(localized: "interrupted", comment: "Mac Activity: progress state for VoiceOver")
        case .stopped, .done, .doneWithFailures: nil
        }
        return [percent, state].compactMap { $0 }.joined(separator: ", ")
    }

    private var symbol: String {
        switch job.state {
        case .running, .finishing: job.kind == .commonPhotosUndo ? "arrow.uturn.backward" : "square.on.square"
        case .paused, .interrupted, .owesFinish: "pause.fill"
        case .readyToMove: "arrow.down.to.line"
        case .stopped: "stop.fill"
        case .done: job.kind == .commonPhotosUndo ? "arrow.uturn.backward" : "checkmark"
        case .doneWithFailures: "exclamationmark.triangle"
        }
    }

    private var tileBackground: Color {
        switch job.state {
        case .running, .finishing, .readyToMove: MacTheme.accentSoft
        case .done: MacTheme.greenSoft
        default: MacTheme.rowSelection
        }
    }

    private var tileForeground: Color {
        switch job.state {
        case .running, .finishing, .readyToMove: MacTheme.accent
        case .done: Color.green
        case .doneWithFailures: Color(nsColor: .systemRed)
        default: .secondary
        }
    }
}
