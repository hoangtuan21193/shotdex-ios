import SwiftUI

/// Settings › Sources (boards `MAC_SettingsSources`, `MAC_SettingsSourcesCache`).
/// So far Photo Sources (AC-72) and Index (AC-70); adding a folder, drives,
/// previews and the index commands come with their tasks (plan
/// 2026-11-04-mac-settings-panes).
struct MacSourcesSettings: View {
    var body: some View {
        ScrollViewReader { proxy in
            Form {
                MacPhotoSourcesSection().id("sources")
                MacDrivesIndexingSection().id("drives")
                MacPreviewsSection().id("previews")
                MacIndexSettingsSection().id("index")
            }
            .formStyle(.grouped)
            #if DEBUG
            // `-ShotDexSettingsScroll previews`: a group below the fold, for screenshots.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "-ShotDexSettingsScroll"), index + 1 < arguments.count else { return }
                try? await Task.sleep(for: .seconds(2))
                proxy.scrollTo(arguments[index + 1], anchor: .top)
            }
            #endif
        }
    }
}

/// Settings › Sources › Index: how far a run is, or what the index holds and
/// when it last ran — the place to see indexing (FS-18.04 §3).
struct MacIndexSettingsSection: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var counts = IndexStatusLine.Counts(photos: 0, videos: 0)
    @State private var lastIndexed: Date?
    /// Photos not read yet, for Paused on battery.
    @State private var waiting = 0
    /// Cameras whose sensor format nobody knows yet, for Review….
    @State private var unknownCameras = 0
    @State private var isConfirmingClear = false
    @State private var clearFailure: String?

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
        if let library, !library.isIndexing, library.powerHold == .battery, waiting > 0 { return .pausedOnBattery(waiting: waiting) }
        guard let library, library.isIndexing else { return .upToDate(lastIndexed: lastIndexed) }
        // A run that has not counted its work yet is still a run.
        guard let progress = library.indexProgress, progress.total > 0 else { return .preparing }
        return .indexing(processed: progress.processed, total: progress.total)
    }

    /// Counts move every 500 reads and when a run starts or ends, not every tick.
    private var refreshKey: String {
        "\(library?.isIndexing ?? false)-\(library?.powerHold == .battery)-\((library?.indexProgress?.processed ?? 0) / 500)"
    }

    var body: some View {
        Section {
            // The "indexed … ago" part ages while the pane stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(alignment: .center, spacing: 8) {
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
                Spacer(minLength: 8)
                // A run going reads everything already. A run started here goes even on battery.
                Button(String(localized: "Re-index Library", comment: "Mac Settings › Index: read every photo again")) {
                    dependencies.library?.startIndexing(fullReindex: true, manual: true)
                }
                .disabled(dependencies.library == nil || dependencies.library?.isIndexing == true)
                .help(String(localized: "Reads every photo in Photos again; folders, drives and servers are read again from their own Re-index. Can take hours for a large library.", comment: "Mac Settings › Index: Re-index Library help"))
                }
            }
            LabeledContent {
                Button(String(localized: "Review…", comment: "Mac Settings › Index: open the camera list")) {
                    NotificationCenter.default.post(name: .macSettingsShowPane, object: MacSettingsPane.cameras.rawValue)
                }
                .disabled(unknownCameras == 0)
                .accessibilityLabel(String(localized: "Review Unknown Cameras", comment: "Mac Settings › Index: VoiceOver"))
            } label: {
                Text("Camera Database", comment: "Mac Settings › Index row")
                Text(unknownCameras == 0
                     ? String(localized: "Every camera has a sensor format", comment: "Mac Settings › Index: no unknown cameras")
                     : unknownCameras == 1
                     ? String(localized: "1 camera needs a sensor format", comment: "Mac Settings › Index: one unknown camera")
                     : String(localized: "\(unknownCameras, format: .number) cameras need a sensor format", comment: "Mac Settings › Index: unknown cameras"))
            }
            LabeledContent {
                Button(String(localized: "Clear…", comment: "Mac Settings › Index: clear the local metadata index"), role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(dependencies.library == nil || dependencies.library?.isIndexRunActive == true)
                .accessibilityLabel(String(localized: "Clear Local Metadata Index", comment: "Mac Settings › Index: VoiceOver"))
            } label: {
                Text("Clear Local Metadata Index", comment: "Mac Settings › Index row")
                Text(dependencies.library?.isIndexRunActive == true
                     ? String(localized: "Available when indexing finishes", comment: "Mac Settings › Index: why Clear is off")
                     : String(localized: "Forgets what was read from your photos and reads them again", comment: "Mac Settings › Index row explanation"))
            }
        } header: {
            Text("Index", comment: "Mac Settings › Sources group")
        }
        .task(id: refreshKey) { await refresh() }
        .alert(String(localized: "The Index Was Not Cleared", comment: "Mac Settings › Index: Clear failed"),
               isPresented: Binding(get: { clearFailure != nil }, set: { if !$0 { clearFailure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Settings › Index: dismiss an error")) {}
        } message: {
            Text(clearFailure ?? "")
        }
        .confirmationDialog(String(localized: "Clear the Local Metadata Index?", comment: "Mac Settings › Index: Clear dialog title"),
                            isPresented: $isConfirmingClear) {
            Button(String(localized: "Clear and Re-index", comment: "Mac Settings › Index: confirm Clear"), role: .destructive) { clearIndex() }
            Button(String(localized: "Cancel", comment: "Mac Settings › Index: keep the index"), role: .cancel) {}
        } message: {
            Text("ShotDex forgets what it read from every photo and reads the library again; this can take a while. Your photos, files, albums, ratings and flags stay.",
                 comment: "Mac Settings › Index: Clear dialog message")
        }
    }

    /// Forgets the camera info read from every photo, then reads the library
    /// again; what the user made — albums, ratings, flags — is kept (AC-80).
    private func clearIndex() {
        let store = dependencies.metadataStore
        Task {
            // 55,000 rows: off the main actor.
            let failed = await Task.detached { () -> String? in
                do { try store.deleteAll(); return nil } catch { return error.localizedDescription }
            }.value
            if let failed {
                clearFailure = failed
                return
            }
            dependencies.library?.reload()
            dependencies.library?.startIndexing(fullReindex: true, manual: true)
            await refresh()
        }
    }

    private func refresh() async {
        if let counts = try? await dependencies.libraryQueries.indexSummaryCounts() { self.counts = counts }
        let store = dependencies.metadataStore
        let seconds = await Task.detached { (try? store.indexState())?.lastIndexedAt }.value
        waiting = await Task.detached { (try? store.unfinishedCount()) ?? 0 }.value
        unknownCameras = await Task.detached { (try? store.unknownCameraModels().count) ?? 0 }.value
        lastIndexed = seconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
