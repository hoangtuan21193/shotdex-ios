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

    struct Stored: Sendable {
        var run: CommonPhotosRun
        var progress: CommonPhotosRunner.Progress
        var done = 0, skipped = 0, failed = 0
    }

    private var runs: MacCommonPhotosRuns { dependencies.commonPhotos }

    var body: some View {
        Group {
            if jobs.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    list
                    foot
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
        .confirmationDialog(stopText.title, isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } })) {
            Button(String(localized: "Stop", comment: "Common photos: end the run for good"), role: .destructive) {
                if let job = stopping { runs.stop(runId: job.id) }
            }
            Button(String(localized: "Keep Going", comment: "Common photos: do not stop the run"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(stopText.message)
        }
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
            input.endedAt = Date(timeIntervalSince1970: TimeInterval(info.run.updatedAt))
            return CommonPhotosJob.job(input)
        }
        .sorted { ($0.rank, stored[$1.id]?.run.createdAt ?? 0) < ($1.rank, stored[$0.id]?.run.createdAt ?? 0) }
    }

    private func readStore() async {
        let (known, cleared) = runs.activityKnownRunIds
        let store = runs.store
        let read = await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            let ids = (known + ((try? store.unfinishedRuns()) ?? []).map(\.id))
                .filter { !cleared.contains($0) && seen.insert($0).inserted }
            var out: [String: Stored] = [:]
            for id in ids {
                guard let run = (try? store.run(id: id)) ?? nil else { continue }
                let items = (try? store.items(runId: id)) ?? []
                let done = items.filter(\.isDone)
                out[id] = Stored(run: run,
                                 progress: CommonPhotosRunner.Progress(doneCount: done.count, totalCount: items.count,
                                                                       doneBytes: done.reduce(0) { $0 + $1.size },
                                                                       totalBytes: items.reduce(0) { $0 + $1.size }),
                                 done: items.filter { $0.status == .copied || $0.status == .moved }.count,
                                 skipped: items.filter { $0.status == .skipped }.count,
                                 failed: items.filter { $0.status == .failed }.count)
            }
            return out
        }.value
        // A newer read (a later generation) has the say.
        guard !Task.isCancelled else { return }
        stored = read
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
            Text("Closing this window doesn’t stop anything — jobs keep running and show at the foot of the sidebar. A job stopped by quitting ShotDex comes back here with Resume.",
                 comment: "Mac Activity: what closing the window does")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Clear Finished", comment: "Mac Activity: remove every row that is over")) {
                runs.clear(runIds: jobs.filter(\.isOver).map(\.id))
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
        case .clear: runs.clear(runIds: [job.id])
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
        case .clear:
            textButton(String(localized: "Clear", comment: "Mac Activity: remove a row that is over"), action)
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
        case .interrupted, .owesFinish: String(localized: "interrupted", comment: "Mac Activity: progress state for VoiceOver")
        case .stopped, .done, .doneWithFailures: nil
        }
        return [percent, state].compactMap { $0 }.joined(separator: ", ")
    }

    private var symbol: String {
        switch job.state {
        case .running, .finishing: "square.on.square"
        case .paused, .interrupted, .owesFinish: "pause.fill"
        case .stopped: "stop.fill"
        case .done: "checkmark"
        case .doneWithFailures: "exclamationmark.triangle"
        }
    }

    private var tileBackground: Color {
        switch job.state {
        case .running, .finishing: MacTheme.accentSoft
        case .done: MacTheme.greenSoft
        default: MacTheme.rowSelection
        }
    }

    private var tileForeground: Color {
        switch job.state {
        case .running, .finishing: MacTheme.accent
        case .done: Color.green
        case .doneWithFailures: Color(nsColor: .systemRed)
        default: .secondary
        }
    }
}
