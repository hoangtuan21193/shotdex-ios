import SwiftUI

/// Runs an earlier launch left half done on this connection — a quit or a
/// crash (FS-19.08 §7): "Move to “Shared” interrupted at 120 of 280" with
/// Resume · Discard…, across the top of the connection's browser, where its
/// folders are. Runs this launch has seen show in the sidebar foot and their
/// window instead. A run that cannot resume offers Discard only; Discard
/// asks first and says what has already been done.
struct MacCommonPhotosResumeBanner: View {
    let connectionId: String
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @State private var runs: [(run: CommonPhotosRun, items: [CommonPhotosItem])] = []
    @State private var discarding: (run: CommonPhotosRun, items: [CommonPhotosItem])?
    /// `-ShotDexCommonPhotosResumeAll` fires once per launch.
    private static var hasResumedForDebug = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(runs, id: \.run.id) { entry in
                row(entry)
                Divider()
            }
        }
        .task(id: "\(connectionId)-\(dependencies.commonPhotos.generation)") {
            runs = dependencies.commonPhotos.leftOver(connectionId: connectionId)
            #if DEBUG
            // `-ShotDexCommonPhotosResumeAll`: press Resume on the first, as a test would.
            if !Self.hasResumedForDebug, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosResumeAll"),
               let first = runs.first, first.run.canResume {
                Self.hasResumedForDebug = true
                resume(first.run)
            }
            #endif
        }
        .alert(String(localized: "Discard This Run?", comment: "Common photos banner: confirm Discard"),
               isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
            Button(String(localized: "Discard", comment: "Common photos banner: discard the run"), role: .destructive) {
                // Asked again: it may have been resumed meanwhile.
                if let run = discarding?.run, dependencies.commonPhotos.canDiscard(runId: run.id) {
                    dependencies.commonPhotos.discard(runId: run.id)
                }
                runs = dependencies.commonPhotos.leftOver(connectionId: connectionId)
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            if let discarding {
                Text(MacCommonPhotosWords.whatIsDone(discarding.items, run: discarding.run) + " "
                     + String(localized: "Discard forgets the run and its log; nothing on the server changes.",
                              comment: "Common photos banner: what Discard does"))
            }
        }
    }

    private func resume(_ run: CommonPhotosRun) {
        dependencies.commonPhotos.resume(runId: run.id)
        MacCommonPhotosRunRoute.open(run.id, openWindow)
        runs = dependencies.commonPhotos.leftOver(connectionId: connectionId)
    }

    private func row(_ entry: (run: CommonPhotosRun, items: [CommonPhotosItem])) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(MacCommonPhotosWords.interrupted(entry.run, done: entry.items.filter(\.isDone).count, total: entry.items.count))
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.run.canResume {
                Button(String(localized: "Resume", comment: "Common photos banner: run again from where it stopped")) { resume(entry.run) }
            }
            Button(String(localized: "Discard…", comment: "Common photos banner: forget the run")) { discarding = entry }
                .disabled(!dependencies.commonPhotos.canDiscard(runId: entry.run.id))
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MacTheme.rowAlternate)
    }
}

/// The sidebar's foot for a common-photos run (board `MAC_CommonPhotosRun`):
/// "Common photos · 120 of 280", the percentage and a bar while it goes;
/// "Common photos interrupted at 120 of 280" (or paused) once it is not —
/// a button that opens the run's window. Reads the run itself, so only
/// this view redraws as it moves.
struct MacCommonPhotosFoot: View {
    let runId: String
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @State private var asksStop = false

    var body: some View {
        if let entry = dependencies.commonPhotos.entries[runId] {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button { MacCommonPhotosRunRoute.open(runId, openWindow) } label: {
                        Text(label(entry)).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Show the run's log", comment: "Mac sidebar foot: open the common-photos run"))
                    if isStuck(entry) {
                        // What to do, not only what happened (user 2026-11-08: "Interrupted"
                        // with nothing to press): Resume picks up where it stopped; with
                        // every photo done, Finish writes the log and rescans.
                        Button(entry.position >= entry.progress.totalCount && entry.progress.totalCount > 0
                               ? String(localized: "Finish", comment: "Mac sidebar foot: complete a run whose photos are all done (log, rescan)")
                               : String(localized: "Resume", comment: "Mac sidebar foot: continue an interrupted common-photos run")) {
                            dependencies.commonPhotos.resume(runId: runId)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(MacTheme.accent)
                        .fontWeight(.semibold)
                        if dependencies.commonPhotos.canStop(runId: runId) {
                            Button { asksStop = true } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help(String(localized: "Stop this run", comment: "Mac sidebar foot: stop an interrupted common-photos run for good"))
                                .accessibilityLabel(String(localized: "Stop this run", comment: "Mac sidebar foot: stop an interrupted common-photos run for good"))
                        }
                    } else {
                        Text(state(entry)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                ProgressView(value: entry.fraction).progressViewStyle(.linear).tint(MacTheme.accent)
                if let problem = entry.problem, isStuck(entry) {
                    Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if isStuck(entry) {
                    Text(entry.isPausedByUser
                         ? String(localized: "Paused", comment: "Mac sidebar foot: a common-photos run is paused")
                         : String(localized: "Interrupted — photos already done stay done.",
                                  comment: "Mac sidebar foot: a common-photos run stopped by a quit or an error"))
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MacTheme.rowAlternate, in: RoundedRectangle(cornerRadius: 10))
            .padding(8)
            .accessibilityElement(children: .contain)
            .confirmationDialog(String(localized: "Stop this run?", comment: "Mac sidebar foot: confirm Stop of an interrupted run"),
                                isPresented: $asksStop) {
                Button(String(localized: "Stop Run", comment: "Mac sidebar foot: stop an interrupted run"), role: .destructive) {
                    dependencies.commonPhotos.stop(runId: runId)
                }
                Button(String(localized: "Keep It", comment: "Mac sidebar foot: keep an interrupted run to resume later"), role: .cancel) {}
            } message: {
                Text("Photos already copied or moved stay where they are. The rest won't be done, and the run can't be resumed.",
                     comment: "Mac sidebar foot: what stopping an interrupted run does")
            }
        }
    }

    /// Not going anywhere: the user can Resume or Stop it.
    private func isStuck(_ entry: MacCommonPhotosRuns.Entry) -> Bool {
        !entry.isRunning && !entry.isRunningElsewhere
    }

    /// "Common photos · 120 of 280" — the same count the window shows.
    private func label(_ entry: MacCommonPhotosRuns.Entry) -> String {
        let position = String(localized: "\(entry.position.formatted()) of \(entry.progress.totalCount.formatted())",
                              comment: "Mac sidebar foot: photo N of M")
        return entry.run.isUndo
            ? String(localized: "Undo · \(position)", comment: "Mac sidebar foot: an undo of a common-photos run")
            : String(localized: "Common photos · \(position)", comment: "Mac sidebar foot: a common-photos run")
    }

    /// The percentage while it goes here, or that the helper runs it.
    private func state(_ entry: MacCommonPhotosRuns.Entry) -> String {
        if entry.isRunningElsewhere {
            return String(localized: "In background", comment: "Mac sidebar foot: the helper runs this common-photos run")
        }
        return entry.fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
