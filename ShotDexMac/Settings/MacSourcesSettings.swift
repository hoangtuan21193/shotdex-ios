import SwiftUI

/// Settings › Sources (boards `MAC_SettingsSources`, `MAC_SettingsSourcesCache`).
/// So far Photo Sources (AC-72) and Index (AC-70); adding a folder, drives,
/// previews and the index commands come with their tasks (plan
/// 2026-11-04-mac-settings-panes).
struct MacSourcesSettings: View {
    var body: some View {
        Form {
            MacPhotoSourcesSection()
            MacIndexSettingsSection()
        }
        .formStyle(.grouped)
    }
}

/// Settings › Sources › Index: how far a run is, or what the index holds and
/// when it last ran — the place to see indexing (FS-18.04 §3).
struct MacIndexSettingsSection: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var counts = IndexStatusLine.Counts(photos: 0, videos: 0)
    @State private var lastIndexed: Date?

    private var library: LibraryModel? { dependencies.library }

    private var state: IndexStatusLine.State {
        #if DEBUG
        // `-ShotDexIndexPreview 12400/55231`: a run in progress, for screenshots of the demo library.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ShotDexIndexPreview"), index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 { return .indexing(processed: parts[0], total: parts[1]) }
        }
        #endif
        guard let library, library.isIndexing else { return .upToDate(lastIndexed: lastIndexed) }
        // A run that has not counted its work yet is still a run.
        guard let progress = library.indexProgress, progress.total > 0 else { return .preparing }
        return .indexing(processed: progress.processed, total: progress.total)
    }

    /// Counts move every 500 reads and when a run starts or ends, not every tick.
    private var refreshKey: String {
        "\(library?.isIndexing ?? false)-\((library?.indexProgress?.processed ?? 0) / 500)"
    }

    var body: some View {
        Section {
            // The "indexed … ago" part ages while the pane stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(IndexStatusLine.title(state, counts: counts))
                        .monospacedDigit()
                    if let detail = IndexStatusLine.detail(state, counts: counts, now: context.date) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if state == .preparing {
                        ProgressView().progressViewStyle(.linear).frame(maxWidth: 240).accessibilityHidden(true)
                    } else if let fraction = IndexStatusLine.fraction(state) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(MacTheme.accent)
                            .frame(maxWidth: 240)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Index", comment: "Mac Settings › Sources group")
        }
        .task(id: refreshKey) { await refresh() }
    }

    private func refresh() async {
        if let counts = try? await dependencies.libraryQueries.indexSummaryCounts() { self.counts = counts }
        let store = dependencies.metadataStore
        let seconds = await Task.detached { (try? store.indexState())?.lastIndexedAt }.value
        lastIndexed = seconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
