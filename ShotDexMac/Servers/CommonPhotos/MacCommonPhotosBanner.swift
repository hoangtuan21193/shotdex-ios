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
        openWindow(id: MacCommonPhotosRunWindow.id, value: run.id)
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

    var body: some View {
        if let entry = dependencies.commonPhotos.entries[runId] {
            Button { openWindow(id: MacCommonPhotosRunWindow.id, value: runId) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label(entry)).foregroundStyle(.primary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(state(entry)).foregroundStyle(entry.isRunning ? .secondary : Color.orange).lineLimit(1)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    ProgressView(value: entry.fraction).progressViewStyle(.linear).tint(MacTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MacTheme.rowAlternate, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .help(String(localized: "Show the run's window", comment: "Mac sidebar foot: open the common-photos window"))
            .accessibilityElement(children: .combine)
        }
    }

    /// "Common photos · 120 of 280" — the same count the window shows.
    private func label(_ entry: MacCommonPhotosRuns.Entry) -> String {
        let position = String(localized: "\(entry.position.formatted()) of \(entry.progress.totalCount.formatted())",
                              comment: "Mac sidebar foot: photo N of M")
        return String(localized: "Common photos · \(position)", comment: "Mac sidebar foot: a common-photos run")
    }

    /// The percentage while it goes, else why it is not going.
    private func state(_ entry: MacCommonPhotosRuns.Entry) -> String {
        if entry.isRunning { return entry.fraction.formatted(.percent.precision(.fractionLength(0))) }
        return entry.isPausedByUser
            ? String(localized: "Paused", comment: "Mac sidebar foot: a common-photos run is paused")
            : String(localized: "Interrupted", comment: "Mac sidebar foot: a common-photos run was interrupted")
    }
}
