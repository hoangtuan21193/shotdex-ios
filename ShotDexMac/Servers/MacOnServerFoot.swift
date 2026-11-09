import Observation
import SwiftUI

/// How far the On Server check has come, for the sidebar foot (FS-19.07 §7,
/// user 2026-11-08: "no progress anywhere"): the first server source's
/// counts, on the folder the smart albums ask about when they agree on one,
/// read off the main actor once per batch of the check — not per
/// frame. Shown while a pass runs, something waits, or photos are left.
@MainActor
@Observable
final class MacOnServerStatus {
    private(set) var line: String?
    private(set) var fraction: Double?
    private(set) var isIncomplete = false
    @ObservationIgnored private var readGeneration = -1

    func refresh(check: OnServerCheck, database: AppDatabase) async {
        guard check.generation != readGeneration else { return }
        readGeneration = check.generation
        let (source, queries) = await Task.detached(priority: .utility) {
            ((try? SourceStore(database: database).sources())?.first(where: { $0.kind == "server" }),
             ((try? SmartAlbumStore(database: database).fetchAllOrdered()) ?? []).map(\.query))
        }.value
        guard let source else {
            line = nil
            fraction = nil
            isIncomplete = false
            return
        }
        let sourceId = source.id
        // The folder the smart albums ask about, so the count is the album's (FS-19.07 §7).
        let folder = OnServerProgressLine.albumFolder(queries, sourceId: sourceId)
        // The same read a smart album over this source asks for: one at a time, shared.
        guard let progress = await OnServerReadGate.shared.value("progress:\(sourceId):\(folder ?? "")", database: database, {
            try OnServerProgressQueries(database: database).progress(sourceId: sourceId, folder: folder)
        }) else { return }
        let (id, name) = (source.id, source.name)
        let wait = check.waits[id] ?? (progress.checked < progress.total ? check.photosWait : nil)
        line = OnServerProgressLine.lines(.init(progress: progress, wait: wait, finishedAt: check.finishedAt,
                                                sourceName: name, folder: folder, thisDevice: .mac)).first
        fraction = progress.total > 0 ? min(1, Double(progress.checked) / Double(progress.total)) : nil
        isIncomplete = progress.checked < progress.total
    }

    func isShown(_ check: OnServerCheck) -> Bool {
        line != nil && (isIncomplete || check.isRunning || !check.waits.isEmpty || check.photosWait != nil)
    }
}

/// The sidebar foot while the On Server check has work: `Checking On
/// Server`, then the words a smart album shows — `Checking · 1,240 of
/// 23,904 · 38 GB to download`, or what it waits for — and a bar. A click
/// opens On Server.
struct MacOnServerFoot: View {
    let status: MacOnServerStatus
    /// The index's own line, kept under it while both run.
    var indexLine: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Checking On Server", comment: "Mac sidebar foot: the on-server check is matching photos with server files")
                    .lineLimit(1)
                if let line = status.line {
                    Text(line).foregroundStyle(.secondary).lineLimit(2).monospacedDigit()
                }
                if let fraction = status.fraction {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MacTheme.fill)
                            Capsule().fill(MacTheme.accent).frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                }
                if let indexLine {
                    Text(indexLine).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .help(String(localized: "Show what runs in Activity", comment: "Mac sidebar foot: tooltip, opens Activity on its Background list"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
