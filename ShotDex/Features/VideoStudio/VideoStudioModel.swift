import AVFoundation
import Photos
import SwiftUI
import ShotDexKit

/// State holder for the Video Studio. Owns the recipe, the loaded sources,
/// the preview player, and the export flow.
///
/// Edits rebuild the preview in three tiers (cheapest that covers the change):
/// - volume/mute/fade → assign a new `audioMix` only (playback uninterrupted)
/// - filter/adjustments/overlays → assign a new `videoComposition` only
/// - structure (reorder, trim, durations, transition, music track, rotate) →
///   full composition rebuild, debounced 300 ms, playhead restored.
@MainActor @Observable
final class VideoStudioModel {
    enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }

    enum ExportState: Equatable {
        case idle
        case exporting(Double)
        case saving
        case failed(String)
    }

    /// Which object the contextual bottom sheet reskins for. Purely derived
    /// from the selection.
    enum InspectorTarget: Equatable {
        case none, clip, text, music
    }

    /// The selected-text sheet's sub-panel: transform (content/size/opacity/
    /// timing), font (family + bold/italic), colour, alignment, style
    /// (outline/shadow), or animation. Reskins the sheet's param zone rather
    /// than stacking another sheet on top.
    enum TextTool: Equatable {
        /// The words: the text field at the top of the panel, focused, with
        /// the keyboard up — what Text opens a new block on (FS-12.04 §3).
        case edit
        case transform, font, color, align, style, animate
    }

    let mode: VideoStudioMode
    var onSaved: ((String) -> Void)?

    private let service: VideoStudioService
    let photoLibrary: PhotoLibraryService
    private let overlayFontRecents: OverlayFontRecentsStore
    let overlayImages: OverlayImageStore

    var recipe: VideoProjectRecipe {
        didSet {
            // Every change of the project — undoable or not — makes the
            // draft write itself a second later (FS-12.18 §2). Not while the
            // sources load: that only fills in what the media turned out to
            // be, and an opened project is not an edited one.
            guard !isLoadingSources, recipe != oldValue else { return }
            drafts?.schedule { [weak self] in self?.draftSnapshot() }
        }
    }
    /// Loaded media by clip id. A source outlives its clip's removal from
    /// the recipe — Replace, Delete — because ✕ and Undo can bring the clip
    /// back, and a clip whose source is gone is skipped by the builder: it
    /// would vanish from the preview with no word. Sources are asset
    /// references, not pixels, so keeping them costs next to nothing.
    var sources: [UUID: VideoClipSource] = [:]
    private(set) var phase: Phase = .loading
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var layout: VideoCompositionBuilder.Layout?

    private(set) var selectedClipID: UUID?
    private(set) var selectedOverlayID: UUID?
    private(set) var selectedMusicID: UUID?
    /// Set when the user taps a transition chip; drives the transition picker.
    var editingTransitionIndex: Int?
    /// The tool panel open when nothing is selected — Look or Video
    /// Settings (FS-12.04 §4). Mutually exclusive with the selection.
    var activeToolPanel: VideoToolPanel?
    /// Which of Filter · Adjust · Color the Look panel shows.
    var lookTab: VideoLookTab = .filter
    /// The selected-text sheet's sub-panel.
    var inspectorTextTool: TextTool = .transform
    private(set) var hasEdits = false

    /// Decoded waveform buckets (0…1) per music track, for the audio bands.
    /// Keyed by `MusicTrack.id`; a track is absent until its decode lands.
    private(set) var musicWaveforms: [UUID: [Float]] = [:]
    /// Decodes are cached by source URL so several tracks over the same file
    /// only pay for one pass.
    private var waveformsByURL: [String: [Float]] = [:]
    private var waveformTasks: [UUID: Task<Void, Never>] = [:]

    /// Bumped to ask the timeline to scroll the whole project into view.
    private(set) var fitToWindowToken = 0

    /// True while the before/after button is held — the look (filter /
    /// adjustments / overlays) is stripped from the preview.
    private(set) var showsOriginal = false

    private(set) var currentTime: Double = 0
    private(set) var totalDuration: Double = 0
    private(set) var isPlaying = false
    var isScrubbing = false
    /// Scrub seek gate: at most one seek in flight; the newest requested time
    /// wins when the previous seek lands.
    private var isSeekInFlight = false
    private var pendingScrubTime: Double?


    var exportState: ExportState = .idle
    private(set) var savedAssetID: String?
    var errorMessage: String?
    /// Set for a project of server photos.
    let serverWorkDirectory: URL?
    /// The server photos' copies on this device, by clip id.
    let serverFiles: [String: URL]
    /// The exported video of a server run, waiting for the export sheet.
    var composedFile: URL?

    var isServerRun: Bool { serverWorkDirectory != nil }

    /// Files dropped from another app are imported into Photos first, so a
    /// project of server photos refuses them (FS-17.06 §5b).
    var acceptsFilesFromOtherApps: Bool { !isServerRun }

    /// The copy on disk behind a clip, for a server photo; nil for a
    /// library asset. Thumbnails read it instead of PhotoKit.
    func serverFileURL(for assetID: String) -> URL? { serverFiles[assetID] }

    var lastFont = OverlayFontChoice.system

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rebuildTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    /// Media dropped on the timeline from another app, being imported into
    /// the photo library. Held so leaving the studio stops it: a drop that
    /// lands after `close()` appends clips to a project the user believes
    /// they shut, on a model whose player and observers are already gone.
    var dropImportTask: Task<Void, Never>?
    private var isAudioSessionActive = false

    convenience init(
        assets: [PHAsset],
        mode: VideoStudioMode,
        service: VideoStudioService,
        photoLibrary: PhotoLibraryService,
        overlayFontRecents: OverlayFontRecentsStore,
        overlayImages: OverlayImageStore,
        creationStore: CreationStore? = nil,
        restoring: Creation? = nil
    ) {
        self.init(
            photos: assets.map(PhotoEditOrigin.asset), mode: mode, service: service, photoLibrary: photoLibrary,
            overlayFontRecents: overlayFontRecents, overlayImages: overlayImages,
            creationStore: creationStore, restoring: restoring
        )
    }

    init(
        photos: [PhotoEditOrigin],
        mode: VideoStudioMode,
        service: VideoStudioService,
        photoLibrary: PhotoLibraryService,
        overlayFontRecents: OverlayFontRecentsStore,
        overlayImages: OverlayImageStore,
        creationStore: CreationStore? = nil,
        /// Reopening a saved video: the stored recipe stands in for the one
        /// built from `assets`. `load()` then resolves sources for *its*
        /// clips, so trims, speeds, captions and music all come back.
        restoring: Creation? = nil,
        /// A project of server photos (FS-17.06 §5b): Export stops at the
        /// file, which goes to the export sheet instead of Photos.
        serverWorkDirectory: URL? = nil
    ) {
        self.serverWorkDirectory = serverWorkDirectory
        self.serverFiles = Dictionary(
            photos.compactMap { photo in photo.serverFile.map { (photo.id, $0.primaryURL) } },
            uniquingKeysWith: { first, _ in first }
        )
        service.setServerFiles(serverFiles)
        self.mode = mode
        self.service = service
        self.photoLibrary = photoLibrary
        self.overlayFontRecents = overlayFontRecents
        self.overlayImages = overlayImages
        self.creationStore = creationStore
        self.creationID = restoring?.id ?? UUID().uuidString
        self.drafts = creationStore.map { store in
            VideoDraftAutosave(write: { try store.saveDraft($0) })
        }
        #if DEBUG
        // `-ShotDexFailDraftWrites`: a UI route photographs the failed-save
        // banner and Back's alert (FS-12.18 §6), which a working disk never
        // shows.
        if creationStore != nil, ProcessInfo.processInfo.arguments.contains("-ShotDexFailDraftWrites") {
            self.drafts = VideoDraftAutosave(write: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        }
        #endif
        if let stored = restoring?.videoRecipe {
            self.recipe = stored
        } else {
            self.recipe = VideoProjectRecipe(
                clips: photos.map { photo in
                    VideoClip(
                        assetID: photo.id,
                        kind: photo.asset?.mediaType == .video ? .video : .photo
                    )
                }
            )
        }
        recipe.syncTransitionsWithClips()
        // The timeline's length is known from the clips before any preview
        // is built; the playhead can stand somewhere from the start.
        totalDuration = clipPlacements.last?.end ?? 0
        if restoring != nil {
            // Reopened (FS-12.18 §3): back where the playhead was, nothing
            // selected, no panel — even for a single video, which a fresh
            // edit opens with its clip selected.
            currentTime = min(max(0, recipe.playhead ?? 0), totalDuration)
            recipe.playhead = nil
        } else if mode == .singleVideo, let first = recipe.clips.first?.id {
            selectedClipID = first
            beginSession(.clip(first))
        }
        observeBackgrounding()
    }

    /// Where a finished video is recorded so it can be reopened, and the id
    /// of this project's row. Exporting a reopened video updates that row
    /// rather than making a second one.
    private let creationStore: CreationStore?
    let creationID: String

    // MARK: - Draft (FS-12.18)

    /// Writes the project as a draft as it is edited. Nil for a project of
    /// server photos, which has no draft (FS-12.18 §2), and in previews.
    var drafts: VideoDraftAutosave?
    /// True while `load()` resolves the sources, when recipe changes are the
    /// media being measured rather than the user editing.
    private var isLoadingSources = false

    /// The row a draft write stores: this project's recipe, under its id.
    /// The store keeps what the row already knew (created, exported).
    func draftSnapshot() -> Creation? {
        var stored = recipe
        stored.playhead = currentTime
        return try? Creation.video(recipe: stored, assetId: nil, id: creationID)
    }

    /// Writes the draft now, edited or not: a project the user opened and
    /// left at once is still kept (FS-12.18 §2) — "nothing is lost" is a
    /// simpler promise than guessing whether they wanted it. Nothing is
    /// written while the sources load or after they failed to, so a project
    /// that never opened cannot overwrite the draft it came from. Returns
    /// whether the project is on disk.
    @discardableResult
    func saveDraftNow() async -> Bool {
        guard let drafts else { return true }
        guard !isLoadingSources, !isFailedLoad else {
            drafts.cancel()
            return true
        }
        return await drafts.saveNow(draftSnapshot())
    }

    /// The last draft write failed (FS-12.18 §6): the banner is up, the
    /// project in memory is untouched and editing goes on.
    var hasFailedDraftSave: Bool { drafts?.hasFailedSave == true }

    /// The banner's Try Again: the same write, now.
    func retryDraftSave() {
        Task { await saveDraftNow() }
    }

    private var isFailedLoad: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// The app going to the background writes the draft at once
    /// (FS-12.18 §2): the system may end the process from there without
    /// another word, and a second of edits is all a crash should cost.
    private var backgroundObserver: NSObjectProtocol?

    private func observeBackgrounding() {
        guard drafts != nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveDraftInBackground() }
        }
    }

    /// The scene changed under the studio — the Duo folded or opened, a
    /// Stage Manager window closed or left the foreground (FS-12.18 §2).
    /// Written at once: the layout that comes next is a different screen,
    /// and the window may not come back.
    func sceneDidChange() {
        saveDraftInBackground()
    }

    /// Writes the draft under a background-task assertion, so the write
    /// finishes even though the app is on its way out.
    func saveDraftInBackground() {
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "video-draft")
        Task {
            await saveDraftNow()
            if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
        }
    }

    /// What Back leads to.
    enum BackOutcome: Equatable {
        /// The project is on disk (or has nowhere to go): close the studio.
        case close
        /// A project of server photos with edits: those have no draft, so
        /// Back still asks before throwing the work away (FS-17.06 §5).
        case confirmDiscard
        /// The draft could not be written; the studio stays open.
        case saveFailed
    }

    /// Back (FS-12.18 §2, FS-12.04 §5): keeps what the open selection did —
    /// Back is ✓, never ✕ — writes the draft at once and lets the studio
    /// close. No "Discard this video?": nothing is discarded.
    func back() async -> BackOutcome {
        clearSelection()
        if isServerRun { return hasEdits ? .confirmDiscard : .close }
        return await saveDraftNow() ? .close : .saveFailed
    }

    var selectedClip: VideoClip? {
        guard let selectedClipID else { return nil }
        return recipe.clips.first { $0.id == selectedClipID }
    }

    var selectedTimedOverlay: TimedOverlay? {
        guard let selectedOverlayID else { return nil }
        return recipe.overlays.first { $0.id == selectedOverlayID }
    }

    var selectedOverlay: PhotoOverlay? {
        selectedTimedOverlay?.overlay
    }

    var selectedMusicTrack: MusicTrack? {
        guard let selectedMusicID else { return nil }
        return recipe.musicTracks.first { $0.id == selectedMusicID }
    }

    /// Which object the inspector reskins for — selection is single-target.
    var inspectorTarget: InspectorTarget {
        if selectedOverlayID != nil { return .text }
        if selectedClipID != nil { return .clip }
        if selectedMusicID != nil { return .music }
        return .none
    }

    // MARK: - Selection and sessions (FS-12.04 §5)

    /// The open selection session: what is being edited, the project as it
    /// was when editing began, and where its undo steps start. Nil when
    /// nothing is selected and no tool panel is open.
    private(set) var session: VideoEditSession?

    /// Opens a session on `target`, remembering the project as it is now.
    private func beginSession(_ target: VideoEditSession.Target) {
        session = VideoEditSession(target: target, startRecipe: recipe, checkpoint: history.checkpoint)
    }

    /// Points the open session at an item that took the selected one's
    /// place (Replace), keeping its start and its steps.
    private func retargetSession(_ target: VideoEditSession.Target) {
        guard let current = session else {
            beginSession(target)
            return
        }
        var moved = VideoEditSession(target: target, startRecipe: current.startRecipe, checkpoint: current.checkpoint)
        moved.isCollapsed = current.isCollapsed
        session = moved
    }

    /// Ends the session keeping every step it made — the ✓ half of the
    /// rule. Each step stays its own undo step.
    private func endSession() {
        session = nil
    }

    private func deselectAll() {
        selectedClipID = nil
        selectedOverlayID = nil
        selectedMusicID = nil
        activeToolPanel = nil
    }

    /// The name the footer shows for the selected item (FS-12.04 §5).
    var selectionTitle: VideoItemTitle.Lines? {
        if let id = selectedClipID, let index = recipe.clips.firstIndex(where: { $0.id == id }) {
            return VideoItemTitle.clip(recipe.clips[index], index: index)
        }
        if let timed = selectedTimedOverlay {
            return VideoItemTitle.overlay(timed, totalDuration: totalDuration)
        }
        if let music = selectedMusicTrack {
            let end = VideoTimelineMath.musicPlacement(
                start: music.start, trimStart: music.trimStart, trimEnd: music.trimEnd,
                sourceDuration: music.sourceDuration, totalDuration: totalDuration
            ).map(\.end) ?? music.end
            return VideoItemTitle.music(music, end: end)
        }
        return nil
    }

    /// ✓: keep, deselect, and the bottom row is the tools again.
    func commitSession() {
        clearSelection()
    }

    /// ✕: the project goes back to exactly what it was when the session
    /// began, every undo step the session made is forgotten — Redo cannot
    /// bring them back — and nothing is selected. With nothing changed it is
    /// only a deselect.
    func cancelSession() {
        guard let session else {
            deselectAll()
            return
        }
        self.session = nil
        history.rollback(to: session.checkpoint)
        deselectAll()
        if recipe != session.startRecipe {
            restore(session.startRecipe)
        }
    }

    func selectClip(_ id: UUID?) {
        guard let id else { clearSelection(); return }
        guard session?.target != .clip(id) else { return }
        endSession()
        deselectAll()
        selectedClipID = id
        beginSession(.clip(id))
    }

    func toggleClip(_ id: UUID) {
        guard !isLaneLocked(.video) else { return }
        selectClip(selectedClipID == id ? nil : id)
    }

    func selectOverlay(_ id: UUID?) {
        guard let id else { clearSelection(); return }
        guard session?.target != .overlay(id) else { return }
        endSession()
        deselectAll()
        selectedOverlayID = id
        inspectorTextTool = .transform
        beginSession(.overlay(id))
    }

    func toggleOverlay(_ id: UUID) {
        guard !isLaneLocked(.overlay(overlayLaneAssignment[id] ?? 0)) else { return }
        selectOverlay(selectedOverlayID == id ? nil : id)
    }

    func selectMusic(_ id: UUID?) {
        guard let id else { clearSelection(); return }
        guard recipe.musicTracks.contains(where: { $0.id == id }) else { return }
        guard session?.target != .music(id) else { return }
        endSession()
        deselectAll()
        selectedMusicID = id
        beginSession(.music(id))
    }

    func toggleMusic(_ id: UUID) {
        guard !isLaneLocked(.music(musicLaneAssignment[id] ?? 0)) else { return }
        selectMusic(selectedMusicID == id ? nil : id)
    }

    // MARK: - Track headers

    /// Lanes the user has locked from the timeline's track headers.
    ///
    /// Session state, not recipe state: a lock is a guard against the wrong
    /// drag while cutting, the way it is in every NLE — it says nothing about
    /// how the project renders, so it has no business in a saved recipe or in
    /// the undo stack. A locked lane refuses selection and refuses every edit
    /// a timeline drag can start.
    private(set) var lockedLanes: Set<VideoTimelineLane> = []

    func isLaneLocked(_ lane: VideoTimelineLane) -> Bool { lockedLanes.contains(lane) }

    func toggleLaneLock(_ lane: VideoTimelineLane) {
        if lockedLanes.contains(lane) {
            lockedLanes.remove(lane)
        } else {
            lockedLanes.insert(lane)
            // A locked lane cannot stay selected, or the inspector goes on
            // offering edits the lane will refuse.
            switch lane {
            case .video:
                if selectedClipID != nil { selectClip(nil) }
            case .overlay(let index):
                if let id = selectedOverlayID, overlayLaneAssignment[id] == index { selectOverlay(nil) }
            case .music(let index):
                if let id = selectedMusicID, musicLaneAssignment[id] == index { selectMusic(nil) }
            }
        }
    }

    /// Whether a clip is locked against edits, by the lane it sits in.
    private func isClipLocked(_: UUID) -> Bool { isLaneLocked(.video) }

    /// The volume the Video track's mute button restores. Zero is a setting a
    /// user can dial, so muting cannot be read off the volume alone.
    private var videoVolumeBeforeMute: Double = 1

    var isVideoTrackMuted: Bool { recipe.videoVolume <= 0 }

    func toggleVideoTrackMuted() {
        if isVideoTrackMuted {
            setVideoVolume(videoVolumeBeforeMute > 0 ? videoVolumeBeforeMute : 1)
        } else {
            videoVolumeBeforeMute = recipe.videoVolume
            setVideoVolume(0)
        }
    }

    /// Music volumes a lane's mute button restores, by track.
    private var musicVolumesBeforeMute: [UUID: Double] = [:]

    func musicTracks(inLane lane: Int) -> [MusicTrack] {
        let assignment = musicLaneAssignment
        return recipe.musicTracks.filter { assignment[$0.id] == lane }
    }

    func isMusicLaneMuted(_ lane: Int) -> Bool {
        let tracks = musicTracks(inLane: lane)
        return !tracks.isEmpty && tracks.allSatisfy { $0.volume <= 0 }
    }

    func toggleMusicLaneMuted(_ lane: Int) {
        let tracks = musicTracks(inLane: lane)
        guard !tracks.isEmpty else { return }
        let muting = !isMusicLaneMuted(lane)
        beginUndoGroup()
        for track in tracks {
            if muting {
                musicVolumesBeforeMute[track.id] = track.volume
                setMusicVolume(0, for: track.id)
            } else {
                let restored = musicVolumesBeforeMute[track.id] ?? 1
                setMusicVolume(restored > 0 ? restored : 1, for: track.id)
            }
        }
        endUndoGroup()
    }

    /// Restarts at the end instead of stopping. Session state: it is how the
    /// user is watching the project, not part of the project.
    var loopsPlayback = false

    /// Ends whatever is open keeping it (= ✓) and deselects: an empty
    /// stretch of timeline, the frame while paused, the grabber, Esc,
    /// Return, Back (FS-12.04 §5).
    func clearSelection() {
        endSession()
        deselectAll()
    }

    /// Deselects everything (keeping what it changed) and opens a tool
    /// panel as a session of its own, or closes the open one with `nil`.
    /// Closing keeps what the panel changed (FS-12.04 §4).
    func showToolPanel(_ panel: VideoToolPanel?) {
        endSession()
        deselectAll()
        guard let panel else { return }
        activeToolPanel = panel
        beginSession(.tool(panel.rawValue))
    }

    /// A tool cell tapped: opens its panel, or closes it if it is the one
    /// open — "tap the open cell again" is close and keep.
    func toggleToolPanel(_ panel: VideoToolPanel) {
        showToolPanel(activeToolPanel == panel ? nil : panel)
    }

    /// True whenever the contextual bottom sheet should be up: something is
    /// selected, or a project-wide tool is open.
    var presentsSheet: Bool {
        inspectorTarget != .none || activeToolPanel != nil
    }

    /// The clip currently under the playhead — the target for playhead-relative
    /// commands (Split, Freeze) issued from the inspector command band.
    var clipIndexUnderPlayhead: Int? {
        VideoTimelineMath.clipIndex(at: currentTime, placements: clipPlacements)
    }

    func fitToWindow() {
        fitToWindowToken &+= 1
    }

    /// Where each clip sits on the timeline, honoring the per-boundary
    /// transition overlaps — the single source of truth the track rows and
    /// the builder share.
    var clipPlacements: [VideoTimelineMath.Placement] {
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(
            requested: recipe.transitions.map(\.requestedOverlap),
            durations: durations
        )
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }

    // MARK: - Timeline lanes

    /// Which lane each overlay (text and sticker alike) draws in, above the
    /// video track. Overlays with no explicit end run to the end of the video.
    var overlayLaneAssignment: [UUID: Int] {
        let total = totalDuration
        return TimelineLaneLayout.assignLanes(recipe.overlays.map { overlay in
            TimelineLaneLayout.Item(
                id: overlay.id,
                start: overlay.start,
                end: overlay.start + (overlay.duration ?? max(0.1, total - overlay.start))
            )
        })
    }

    var overlayLaneCount: Int {
        max(1, TimelineLaneLayout.laneCount(for: overlayLaneAssignment))
    }

    /// Which lane each music track draws in, below the video track.
    var musicLaneAssignment: [UUID: Int] {
        TimelineLaneLayout.assignLanes(recipe.musicTracks.map { music in
            TimelineLaneLayout.Item(id: music.id, start: music.start, end: music.end)
        })
    }

    var musicLaneCount: Int {
        max(1, TimelineLaneLayout.laneCount(for: musicLaneAssignment))
    }

    // MARK: - Load

    func load() async {
        phase = .loading
        isLoadingSources = true
        defer { isLoadingSources = false }
        let loaded = await service.loadSources(for: recipe.clips, maximumStillSize: recipe.canvasSize())
        guard !loaded.sources.isEmpty else {
            phase = .failed(String(localized: "Couldn't load the selected items."))
            return
        }
        sources = loaded.sources
        // Seed video trim windows with the resolved source durations.
        for index in recipe.clips.indices {
            let clip = recipe.clips[index]
            if clip.kind == .video, let duration = loaded.durations[clip.id] {
                measuredSourceDurations[clip.id] = duration
                recipe.clips[index].sourceDuration = duration
                if recipe.clips[index].trimEnd == nil {
                    recipe.clips[index].trimEnd = duration
                }
            }
        }
        // Drop clips whose media never resolved so the timeline matches what
        // the builder will actually use — and say so. A clip that vanishes
        // from the timeline with no word looks identical to a clip the app
        // forgot to add, and the usual cause is an iCloud original that has
        // not come down yet, which the user can do something about.
        let droppedCount = recipe.clips.count(where: { sources[$0.id] == nil })
        recipe.clips.removeAll { sources[$0.id] == nil }
        if droppedCount > 0 {
            errorMessage = droppedCount == 1
                ? String(localized: "One clip couldn't be loaded and was left out. It may still be in iCloud — check your connection and add it again.")
                : String(localized: "\(droppedCount) clips couldn't be loaded and were left out. They may still be in iCloud — check your connection and add them again.")
        }
        recipe.syncTransitionsWithClips()
        reloadWaveforms()
        await rebuildPreview()
        phase = .ready
    }

    func close() {
        // A studio closed some other way than Back (its presenter went
        // away) still writes the change it was waiting to write. The task
        // keeps the model alive until it has.
        if drafts?.isSavePending == true {
            Task { await self.saveDraftNow() }
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
        rebuildTask?.cancel()
        exportTask?.cancel()
        dropImportTask?.cancel()
        for task in waveformTasks.values { task.cancel() }
        waveformTasks.removeAll()
        detachObservers()
        player?.pause()
        player = nil
        playerItem = nil
        if isAudioSessionActive {
            VideoAudioSession.deactivate()
            isAudioSessionActive = false
        }
        service.setServerFiles([:])
        service.cleanupSession()
    }

    // MARK: - Transport

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if !isAudioSessionActive {
                VideoAudioSession.activate()
                isAudioSessionActive = true
            }
            if currentTime >= totalDuration - 0.05 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        currentTime = min(max(seconds, 0), totalDuration)
        player?.seek(
            to: VideoCompositionBuilder.time(currentTime),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: - Timeline scrubbing

    func beginScrub() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
        isScrubbing = true
    }

    /// Continuous scrub updates: `currentTime` follows the finger instantly;
    /// the actual player seeks self-pace behind an in-flight gate so the
    /// composition decodes as fast as it can without a seek pile-up.
    func scrub(to seconds: Double) {
        let clamped = min(max(seconds, 0), totalDuration)
        currentTime = clamped
        guard let player else { return }
        if isSeekInFlight {
            pendingScrubTime = clamped
            return
        }
        isSeekInFlight = true
        player.seek(
            to: VideoCompositionBuilder.time(clamped),
            toleranceBefore: CMTime(value: 30, timescale: 600),
            toleranceAfter: CMTime(value: 30, timescale: 600)
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSeekInFlight = false
                if let pending = self.pendingScrubTime {
                    self.pendingScrubTime = nil
                    self.scrub(to: pending)
                }
            }
        }
    }

    func endScrub(at seconds: Double) {
        pendingScrubTime = nil
        isScrubbing = false
        seek(to: seconds)
    }

    // MARK: - Undo / redo

    /// Whole-recipe snapshots with numbered steps (`VideoEditHistory`).
    private(set) var history = VideoEditHistory()

    /// Snapshot the recipe before a discrete mutation. Slider drags snapshot
    /// once per gesture via `beginUndoGroup`/`endUndoGroup`.
    func pushUndo() {
        history.push(recipe)
    }

    func beginUndoGroup() {
        history.beginGroup(recipe)
    }

    func endUndoGroup() {
        history.endGroup()
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// One step back. Stepping past the start of the open session ends it
    /// — kept, as ✓ keeps — and deselects (FS-12.04 §5).
    func undo() {
        if let session, let newest = history.newestSequence, newest < session.checkpoint {
            endSession()
            deselectAll()
        }
        guard let previous = history.undo(from: recipe) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(from: recipe) else { return }
        restore(next)
    }

    /// Source lengths the media turned out to have, by clip or track id.
    /// They are measured once, at load, and written into the recipe; a
    /// snapshot taken before that write lacks them, so every restore puts
    /// them back rather than leaving a clip that cannot be trimmed.
    private var measuredSourceDurations: [UUID: Double] = [:]

    private func restore(_ snapshot: VideoProjectRecipe) {
        history.endGroup()
        var restored = snapshot
        for index in restored.clips.indices where restored.clips[index].sourceDuration == nil {
            guard let duration = measuredSourceDurations[restored.clips[index].id] else { continue }
            restored.clips[index].sourceDuration = duration
            if restored.clips[index].trimEnd == nil { restored.clips[index].trimEnd = duration }
        }
        for index in restored.musicTracks.indices where restored.musicTracks[index].sourceDuration == nil {
            guard let duration = measuredSourceDurations[restored.musicTracks[index].id] else { continue }
            restored.musicTracks[index].sourceDuration = duration
            if restored.musicTracks[index].trimEnd == nil { restored.musicTracks[index].trimEnd = duration }
        }
        recipe = restored
        if let selectedClipID, !recipe.clips.contains(where: { $0.id == selectedClipID }) {
            self.selectedClipID = nil
        }
        if let selectedOverlayID, !recipe.overlays.contains(where: { $0.id == selectedOverlayID }) {
            self.selectedOverlayID = nil
        }
        if let selectedMusicID, !recipe.musicTracks.contains(where: { $0.id == selectedMusicID }) {
            self.selectedMusicID = nil
        }
        if inspectorTarget == .none, activeToolPanel == nil, session?.target.isItem == true {
            endSession()
        }
        if let index = editingTransitionIndex, !recipe.transitions.indices.contains(index) {
            editingTransitionIndex = nil
        }
        markEdited()
        reloadWaveforms()
        // Always the structural tier: a snapshot can differ in any dimension,
        // and the 300 ms debounce keeps repeated undos cheap.
        schedulePreviewRebuild()
    }

    // MARK: - Structural edits (full rebuild)

    func moveClip(from source: Int, to destination: Int) {
        guard !isLaneLocked(.video) else { return }
        guard recipe.clips.indices.contains(source),
              recipe.clips.indices.contains(destination),
              source != destination
        else { return }
        let clip = recipe.clips.remove(at: source)
        recipe.clips.insert(clip, at: destination)
        markEdited()
        schedulePreviewRebuild()
    }

    func setPhotoDuration(_ duration: Double, for clipID: UUID) {
        guard !isClipLocked(clipID) else { return }
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].photoDuration = min(
            max(duration, VideoClip.photoDurationRange.lowerBound),
            VideoClip.photoDurationRange.upperBound
        )
        markEdited()
        schedulePreviewRebuild()
    }

    func setTrim(start: Double, end: Double, for clipID: UUID) {
        guard !isClipLocked(clipID) else { return }
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }),
              let sourceDuration = recipe.clips[index].sourceDuration
        else { return }
        let clamped = VideoTimelineMath.clampedTrim(
            start: start,
            end: end,
            sourceDuration: sourceDuration
        )
        recipe.clips[index].trimStart = clamped.start
        recipe.clips[index].trimEnd = clamped.end
        markEdited()
        schedulePreviewRebuild()
    }

    func setTransition(_ transition: VideoBoundaryTransition, at boundaryIndex: Int) {
        guard recipe.transitions.indices.contains(boundaryIndex) else { return }
        var clamped = transition
        clamped.duration = min(
            max(clamped.duration, VideoBoundaryTransition.durationRange.lowerBound),
            VideoBoundaryTransition.durationRange.upperBound
        )
        recipe.transitions[boundaryIndex] = clamped
        markEdited()
        schedulePreviewRebuild()
    }

    /// Convenience for an "apply to all boundaries" control.
    func setAllTransitions(_ transition: VideoBoundaryTransition) {
        for index in recipe.transitions.indices {
            recipe.transitions[index] = transition
        }
        markEdited()
        schedulePreviewRebuild()
    }

    /// Deletes a clip as one undo step, whoever asks — the panel's Delete,
    /// the transport's ⋯ menu, a key. The clips after it close up (the track
    /// holds no gaps), and deleting the selected clip ends its session the
    /// way ✓ does (FS-12.04 §5): the delete is a step Undo can take back.
    func deleteClip(_ clipID: UUID) {
        guard recipe.clips.count > 1,
              let index = recipe.clips.firstIndex(where: { $0.id == clipID })
        else { return }
        pushUndo()
        recipe.clips.remove(at: index)
        recipe.syncTransitionsWithClips()
        if selectedClipID == clipID { clearSelection() }
        if let boundary = editingTransitionIndex,
           !recipe.transitions.indices.contains(boundary) {
            editingTransitionIndex = nil
        }
        markEdited()
        schedulePreviewRebuild()
    }

    /// Adds a bed starting at the playhead and selects it. The source's length
    /// resolves asynchronously and seeds the trim window.
    func addMusicTrack(source: MusicSource) {
        var music = MusicTrack(source: source)
        music.start = max(0, min(currentTime, max(0, totalDuration - MusicTrack.minimumDuration)))
        beginAddSession(.music(music.id))
        pushUndo()
        recipe.musicTracks.append(music)
        selectedMusicID = music.id
        markEdited()
        resolveMusicDuration(for: music.id)
        loadWaveform(for: music.id)
        schedulePreviewRebuild()
    }

    func removeMusicTrack(_ id: UUID) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.musicTracks.remove(at: index)
        if selectedMusicID == id { clearSelection() }
        waveformTasks[id]?.cancel()
        waveformTasks[id] = nil
        musicWaveforms[id] = nil
        markEdited()
        schedulePreviewRebuild()
    }

    /// Swaps the audio behind a bed, keeping where it sits but resetting the
    /// trim window to the new source.
    func replaceMusicTrack(_ id: UUID, source: MusicSource) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.musicTracks[index].source = source
        recipe.musicTracks[index].trimStart = 0
        recipe.musicTracks[index].trimEnd = nil
        recipe.musicTracks[index].sourceDuration = nil
        musicWaveforms[id] = nil
        markEdited()
        resolveMusicDuration(for: id)
        loadWaveform(for: id)
        schedulePreviewRebuild()
    }

    func setMusicStart(_ start: Double, for id: UUID) {
        guard !isLaneLocked(.music(musicLaneAssignment[id] ?? 0)) else { return }
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        recipe.musicTracks[index].start = max(
            0,
            min(start, max(0, totalDuration - MusicTrack.minimumDuration))
        )
        markEdited()
        schedulePreviewRebuild()
    }

    func setMusicTrim(start: Double, end: Double, for id: UUID) {
        guard !isLaneLocked(.music(musicLaneAssignment[id] ?? 0)) else { return }
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }),
              let sourceDuration = recipe.musicTracks[index].sourceDuration
        else { return }
        let trimmed = VideoTimelineMath.clampedTrim(
            start: start,
            end: end,
            sourceDuration: sourceDuration
        )
        recipe.musicTracks[index].trimStart = trimmed.start
        recipe.musicTracks[index].trimEnd = trimmed.end
        markEdited()
        schedulePreviewRebuild()
    }

    /// Head trim: the window slides in the source and on the timeline together,
    /// so the audio under the untouched tail never shifts. One undo step.
    func trimMusicHead(by delta: Double, for id: UUID) {
        guard let music = recipe.musicTracks.first(where: { $0.id == id }),
              let sourceDuration = music.sourceDuration
        else { return }
        let end = music.trimEnd ?? sourceDuration
        let lowerBound = max(-music.trimStart, -music.start)
        let upperBound = end - music.trimStart - MusicTrack.minimumDuration
        guard upperBound >= lowerBound else { return }
        let applied = min(max(delta, lowerBound), upperBound)
        guard abs(applied) > 0.0005 else { return }
        beginUndoGroup()
        setMusicTrim(start: music.trimStart + applied, end: end, for: id)
        setMusicStart(music.start + applied, for: id)
        endUndoGroup()
    }

    func importMusic(from pickedURL: URL) {
        do {
            let copied = try service.copyImportedMusic(from: pickedURL)
            addMusicTrack(source: .imported(
                url: copied,
                displayName: pickedURL.deletingPathExtension().lastPathComponent
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveMusicDuration(for id: UUID) {
        guard let music = recipe.musicTracks.first(where: { $0.id == id }) else { return }
        let source = music.source
        Task { [weak self] in
            guard let self else { return }
            guard let duration = await service.loadAudioDuration(for: source) else { return }
            measuredSourceDurations[id] = duration
            guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
            recipe.musicTracks[index].sourceDuration = duration
            if recipe.musicTracks[index].trimEnd == nil {
                recipe.musicTracks[index].trimEnd = duration
            }
            schedulePreviewRebuild()
        }
    }

    func rotateClockwise() {
        recipe.quarterTurns = (recipe.quarterTurns + 1) % 4
        markEdited()
        schedulePreviewRebuild()
    }

    // MARK: - Structural edits (Turn 2)

    /// Output canvas shape — changes `renderSize`, so a full rebuild.
    func setAspect(_ aspect: VideoAspect) {
        guard recipe.aspect != aspect else { return }
        pushUndo()
        recipe.aspect = aspect
        markEdited()
        schedulePreviewRebuild()
    }

    func setSpeed(_ speed: Double, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }),
              recipe.clips[index].kind == .video
        else { return }
        recipe.clips[index].speed = min(
            max(speed, VideoClip.speedRange.lowerBound),
            VideoClip.speedRange.upperBound
        )
        markEdited()
        schedulePreviewRebuild()
    }

    /// Split the clip under the playhead in two at the current time. Children
    /// share the parent's already-loaded source.
    func splitClipUnderPlayhead() {
        let placements = clipPlacements
        guard let index = VideoTimelineMath.clipIndex(at: currentTime, placements: placements),
              index < placements.count
        else { return }
        let localTime = currentTime - placements[index].start
        guard let (first, second) = VideoSplitMath.split(
            recipe.clips[index], atLocalTime: localTime
        ) else { return }
        pushUndo()
        if let source = sources[recipe.clips[index].id] {
            sources[first.id] = source
            sources[second.id] = source
        }
        recipe.clips.replaceSubrange(index...index, with: [first, second])
        recipe.syncTransitionsWithClips()
        selectClip(second.id)
        markEdited()
        schedulePreviewRebuild()
    }

    /// Throw away everything in the clip under the playhead **before** the
    /// playhead, or everything **after** it.
    ///
    /// Resolve's Cut page puts exactly this pair on the left of its transport
    /// row — Trim Start to Playhead and Trim End to Playhead — because the
    /// commonest trim is not "set both ends", it is "lose the run-up" or
    /// "lose the tail", and it wants one tap. ShotDex had only the two-ended
    /// Duration/Trim sliders in the panel.
    ///
    /// On a still it moves `photoDuration`; on a video it moves the trim
    /// window. Either way the clip keeps its place on the track and the rest
    /// of the project shifts to follow, which is what `clipPlacements`
    /// already does for every other length change.
    func trimToPlayhead(_ end: ClipEnd) {
        let placements = clipPlacements
        guard let index = VideoTimelineMath.clipIndex(at: currentTime, placements: placements),
              index < placements.count,
              !isLaneLocked(.video)
        else { return }
        let clip = recipe.clips[index]
        let localTime = currentTime - placements[index].start
        guard localTime > 0, localTime < placements[index].duration else { return }

        switch clip.kind {
        case .photo, .freeze:
            let kept = end == .start ? placements[index].duration - localTime : localTime
            guard kept >= VideoClip.photoDurationRange.lowerBound else { return }
            pushUndo()
            recipe.clips[index].photoDuration = kept
        case .video:
            guard let sourceDuration = clip.sourceDuration else { return }
            // Local time runs at the clip's speed; the trim window does not.
            let sourceTime = clip.trimStart + localTime * max(clip.speed, 0.01)
            let start = end == .start ? sourceTime : clip.trimStart
            let finish = end == .start ? (clip.trimEnd ?? sourceDuration) : sourceTime
            guard finish - start >= VideoClip.minimumClipDuration else { return }
            let clamped = VideoTimelineMath.clampedTrim(
                start: start,
                end: finish,
                sourceDuration: sourceDuration
            )
            pushUndo()
            recipe.clips[index].trimStart = clamped.start
            recipe.clips[index].trimEnd = clamped.end
        }
        markEdited()
        schedulePreviewRebuild()
    }

    /// Which end of a clip a command acts on.
    enum ClipEnd { case start, end }

    // MARK: - Markers

    /// A note at the playhead. Tapping the same spot twice does not stack two
    /// dots on one pixel: a marker within half a second of an existing one is
    /// treated as meaning that one.
    @discardableResult
    func addMarker() -> TimedMarker? {
        let time = max(0, min(currentTime, totalDuration))
        if let existing = marker(near: time) { return existing }
        var marker = TimedMarker(time: time)
        marker.colorIndex = recipe.markers.count % TimedMarker.palette.count
        pushUndo()
        recipe.markers.append(marker)
        recipe.markers.sort { $0.time < $1.time }
        markEdited()
        return marker
    }

    func marker(near time: Double, tolerance: Double = 0.5) -> TimedMarker? {
        recipe.markers.min { abs($0.time - time) < abs($1.time - time) }
            .flatMap { abs($0.time - time) <= tolerance ? $0 : nil }
    }

    func removeMarker(_ id: UUID) {
        guard recipe.markers.contains(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.markers.removeAll { $0.id == id }
        markEdited()
    }

    func setMarkerNote(_ note: String, for id: UUID) {
        guard let index = recipe.markers.firstIndex(where: { $0.id == id }) else { return }
        recipe.markers[index].note = note
        markEdited()
    }

    func cycleMarkerColor(_ id: UUID) {
        guard let index = recipe.markers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.markers[index].colorIndex =
            (recipe.markers[index].clampedColorIndex + 1) % TimedMarker.palette.count
        markEdited()
    }

    /// The next marker after (or before) the playhead — what a "jump to
    /// marker" command needs, and what makes markers worth placing at all.
    func seekToMarker(after: Bool) {
        let candidates = after
            ? recipe.markers.filter { $0.time > currentTime + 0.05 }
            : recipe.markers.filter { $0.time < currentTime - 0.05 }.reversed().map { $0 }
        guard let target = candidates.first else { return }
        seek(to: target.time)
    }

    // MARK: - Snapping

    /// Whether dragging a music bed or a caption sticks to the edits.
    ///
    /// Resolve calls its version the magnetic timeline. The **video** lane
    /// here cannot hold a gap at all — `clipPlacements` lays clips end to end
    /// from their durations, so deleting one closes the space by
    /// construction, and there is nothing to make magnetic. What *can* sit
    /// anywhere is a music bed's start and a caption's window, and those are
    /// exactly what a user wants landing on a cut rather than 40ms past it.
    var snapsToEdits = true

    /// The nearest edit point to `time`, or nil when nothing is close enough.
    /// Candidates are every clip boundary, every marker, and the playhead.
    func snappedTime(_ time: Double, within tolerance: Double) -> Double {
        guard snapsToEdits else { return time }
        var candidates: [Double] = [0, totalDuration, currentTime]
        for placement in clipPlacements {
            candidates.append(placement.start)
            candidates.append(placement.end)
        }
        candidates.append(contentsOf: recipe.markers.map(\.time))
        guard let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }),
              abs(nearest - time) <= tolerance
        else { return time }
        return nearest
    }

    /// Freeze the frame under the playhead: insert a held still right after the
    /// clip it lands in.
    func freezeUnderPlayhead() {
        let placements = clipPlacements
        guard let index = VideoTimelineMath.clipIndex(at: currentTime, placements: placements),
              index < placements.count
        else { return }
        let clip = recipe.clips[index]
        let localTime = currentTime - placements[index].start
        let sourceTime: Double
        switch clip.kind {
        case .video:
            sourceTime = clip.trimStart + localTime * max(clip.speed, VideoClip.speedRange.lowerBound)
        case .freeze:
            sourceTime = clip.freezeSourceTime ?? 0
        case .photo:
            return  // already a still
        }
        pushUndo()
        var freeze = VideoClip(assetID: clip.assetID, kind: .freeze)
        freeze.freezeSourceTime = sourceTime
        freeze.photoDuration = 2
        recipe.clips.insert(freeze, at: index + 1)
        recipe.syncTransitionsWithClips()
        markEdited()
        Task { await loadAndMerge([freeze]) }
    }

    /// Where media the user adds lands on the Video track.
    ///
    /// Resolve names three (Smart Insert, Append at End, Place on Top); the
    /// third needs a second video track, and this composition builder runs
    /// one video lane on alternating A/B tracks so two clips can share a
    /// transition window (spec §7.9). So there are two here, and they are the
    /// two that a single track can honestly offer.
    enum MediaInsertMode: String, CaseIterable, Identifiable, Sendable {
        /// After everything, the way Add has always worked.
        case appendAtEnd
        /// Cut the clip under the playhead and drop the new media into the
        /// seam — Resolve's Smart Insert, on one track.
        case insertAtPlayhead

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appendAtEnd:
                String(localized: "Append at End", comment: "Video Studio media pool: new media goes after the last clip")
            case .insertAtPlayhead:
                String(localized: "Insert at Playhead", comment: "Video Studio media pool: new media is cut into the track where the playhead is")
            }
        }

        var systemImage: String {
            switch self {
            case .appendAtEnd: "arrow.right.to.line"
            case .insertAtPlayhead: "arrow.down.to.line"
            }
        }
    }

    /// Session state: how the user is working right now, not part of the
    /// project.
    var mediaInsertMode: MediaInsertMode = .appendAtEnd

    func appendMedia(_ picks: [VideoMediaPick]) {
        guard !picks.isEmpty else { return }
        let newClips = picks.map { VideoClip(assetID: $0.assetID, kind: $0.kind) }
        pushUndo()
        recipe.clips.append(contentsOf: newClips)
        recipe.syncTransitionsWithClips()
        markEdited()
        Task { await loadAndMerge(newClips) }
    }

    /// Adds media the way `mediaInsertMode` says to.
    ///
    /// Insert-at-playhead splits the clip the playhead is inside first, so the
    /// new media lands on a real boundary rather than on top of a frame the
    /// user was looking at; landing exactly on a boundary (or past the end)
    /// needs no split and just inserts at that index.
    func insertMedia(_ picks: [VideoMediaPick]) {
        guard !picks.isEmpty else { return }
        guard mediaInsertMode == .insertAtPlayhead, !recipe.clips.isEmpty else {
            appendMedia(picks)
            return
        }
        let placements = clipPlacements
        let newClips = picks.map { VideoClip(assetID: $0.assetID, kind: $0.kind) }
        pushUndo()

        var insertAt = recipe.clips.count
        if let index = VideoTimelineMath.clipIndex(at: currentTime, placements: placements),
           index < placements.count {
            let localTime = currentTime - placements[index].start
            if let (first, second) = VideoSplitMath.split(recipe.clips[index], atLocalTime: localTime) {
                if let source = sources[recipe.clips[index].id] {
                    sources[first.id] = source
                    sources[second.id] = source
                }
                recipe.clips.replaceSubrange(index...index, with: [first, second])
                insertAt = index + 1
            } else {
                // The playhead sits on this clip's own edge: nothing to cut,
                // and the seam is already where the user is pointing.
                insertAt = localTime <= 0 ? index : index + 1
            }
        }
        recipe.clips.insert(contentsOf: newClips, at: min(insertAt, recipe.clips.count))
        recipe.syncTransitionsWithClips()
        markEdited()
        Task { await loadAndMerge(newClips) }
    }

    func replaceSelectedClip(with pick: VideoMediaPick) {
        guard let selectedClipID,
              let index = recipe.clips.firstIndex(where: { $0.id == selectedClipID })
        else { return }
        pushUndo()
        let new = VideoClip(assetID: pick.assetID, kind: pick.kind)
        // The old clip's source stays: ✕ or Undo puts the old clip back.
        recipe.clips[index] = new
        recipe.syncTransitionsWithClips()
        // Replace is a step inside the clip's session, not the end of it:
        // the session follows the clip into its new id, so ✕ takes the
        // replacement back with the rest.
        self.selectedClipID = new.id
        retargetSession(.clip(new.id))
        markEdited()
        Task { await loadAndMerge([new]) }
    }

    /// Loads sources for freshly-added clips and merges them in, then rebuilds.
    private func loadAndMerge(_ clips: [VideoClip]) async {
        let loaded = await service.loadSources(for: clips, maximumStillSize: recipe.canvasSize())
        for (id, source) in loaded.sources { sources[id] = source }
        for clip in clips where clip.kind == .video {
            guard let duration = loaded.durations[clip.id],
                  let index = recipe.clips.firstIndex(where: { $0.id == clip.id })
            else { continue }
            measuredSourceDurations[clip.id] = duration
            recipe.clips[index].sourceDuration = duration
            if recipe.clips[index].trimEnd == nil {
                recipe.clips[index].trimEnd = duration
            }
        }
        let failed = clips.filter { sources[$0.id] == nil }.map(\.id)
        if !failed.isEmpty {
            recipe.clips.removeAll { failed.contains($0.id) }
            recipe.syncTransitionsWithClips()
            // Same as the initial load: adding a clip that quietly does not
            // arrive is indistinguishable from the app ignoring the tap.
            errorMessage = failed.count == 1
                ? String(localized: "One clip couldn't be loaded and was left out. It may still be in iCloud — check your connection and add it again.")
                : String(localized: "\(failed.count) clips couldn't be loaded and were left out. They may still be in iCloud — check your connection and add them again.")
        }
        markEdited()
        await rebuildPreview()
    }

    // MARK: - Audio-only edits (audioMix tier)

    func setVideoVolume(_ volume: Double) {
        recipe.videoVolume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    /// One clip's own level, under Video sound (FS-12.08 §2).
    func setClipVolume(_ volume: Double, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].volume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    func setMuted(_ muted: Bool, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].isMuted = muted
        markEdited()
        applyAudioTier()
    }

    func setMusicVolume(_ volume: Double, for id: UUID) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        recipe.musicTracks[index].volume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    func setMusicFadeIn(_ seconds: Double, for id: UUID) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        recipe.musicTracks[index].fadeIn = min(max(seconds, 0), MusicTrack.fadeRange.upperBound)
        markEdited()
        applyAudioTier()
    }

    func setMusicFadeOut(_ seconds: Double, for id: UUID) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        recipe.musicTracks[index].fadeOut = min(max(seconds, 0), MusicTrack.fadeRange.upperBound)
        markEdited()
        applyAudioTier()
    }

    /// Hold-for-original: while true the look (filter, the whole grading
    /// chain, the imported LUT and the overlays) is stripped from the preview
    /// via the cheap video-composition tier. Never touches the recipe, so
    /// releasing restores the edit exactly.
    func setShowsOriginal(_ value: Bool) {
        showsOriginal = value
        guard let playerItem, let layout else { return }
        var preview = recipe
        if value {
            preview.filter = .original
            preview.filterIntensity = 1
            // The whole chain, not one stage: "show me the original" means
            // the picture before the grade, and the grade is every node.
            preview.nodes = [ColorNode()]
            preview.lut = nil
            preview.overlays = []
        }
        service.applyVideoComposition(recipe: preview, layout: layout, to: playerItem)
    }

    // MARK: - Look edits (videoComposition tier)

    func setFilter(_ filter: PhotoFilter) {
        // A tap, not a drag: one snapshot, so picking a look and disliking it
        // is undoable like every other edit in the studio.
        pushUndo()
        recipe.filter = filter
        markEdited()
        applyVideoTier()
    }

    func setFilterIntensity(_ intensity: Double) {
        recipe.filterIntensity = min(max(intensity, 0), 1)
        markEdited()
        applyVideoTier()
    }

    // MARK: - Colour (look tier)

    // MARK: The grading chain

    /// Which node the Color and Adjust panels are editing. Selection is
    /// where the user is looking, not part of the grade, so it lives on the
    /// model and never goes into undo.
    var selectedNodeID: UUID?

    /// The node being edited — the selected one, or the first if nothing is
    /// selected or the selection has been deleted. Writing through this
    /// writes into the recipe, so every existing grade mutator keeps its
    /// one-line shape.
    var activeNode: ColorNode {
        get { recipe.node(selectedNodeID) }
        set {
            let id = newValue.id
            guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
            recipe.nodes[index] = newValue
        }
    }

    var activeNodeIndex: Int { recipe.nodeIndex(selectedNodeID ?? recipe.nodes.first?.id) }

    /// Adds an empty node after the selected one and selects it — the way a
    /// grade grows: balance, then look, then the window.
    func addNode() {
        pushUndo()
        let node = ColorNode()
        let after = recipe.nodeIndex(selectedNodeID)
        recipe.nodes.insert(node, at: min(after + 1, recipe.nodes.count))
        selectedNodeID = node.id
        markEdited()
        applyVideoTier()
    }

    /// A copy of the node, right after it. Resolve's commonest node action
    /// after adding one: take what works and push it further.
    func duplicateNode(_ id: UUID) {
        guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        var copy = recipe.nodes[index]
        copy.id = UUID()
        copy.masks = copy.masks.map { mask in
            var duplicate = mask
            duplicate.id = UUID()
            return duplicate
        }
        recipe.nodes.insert(copy, at: index + 1)
        selectedNodeID = copy.id
        markEdited()
        applyVideoTier()
    }

    /// Deleting the last node leaves a fresh empty one: a grade with no node
    /// is a panel with nothing to edit.
    func deleteNode(_ id: UUID) {
        guard recipe.nodes.contains(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.nodes.removeAll { $0.id == id }
        if recipe.nodes.isEmpty { recipe.nodes = [ColorNode()] }
        if selectedNodeID == id { selectedNodeID = recipe.nodes.first?.id }
        markEdited()
        applyVideoTier()
    }

    /// Bypass. The node stays in the chain and stops doing anything, which is
    /// how a colourist checks what a node is actually contributing.
    func toggleNodeEnabled(_ id: UUID) {
        guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        recipe.nodes[index].isEnabled.toggle()
        markEdited()
        applyVideoTier()
    }

    func renameNode(_ id: UUID, to name: String) {
        guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recipe.nodes[index].name != trimmed else { return }
        pushUndo()
        recipe.nodes[index].name = trimmed
        markEdited()
    }

    /// Moves a node one place along the chain. Order **is** the grade — a
    /// window before a contrast pass and after it are different pictures —
    /// so this is a real edit, not a reshuffle of a list.
    func moveNode(_ id: UUID, by offset: Int) {
        guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < recipe.nodes.count else { return }
        pushUndo()
        let node = recipe.nodes.remove(at: index)
        recipe.nodes.insert(node, at: target)
        markEdited()
        applyVideoTier()
    }

    /// Clears the node's grade without removing it from the chain.
    func resetNode(_ id: UUID) {
        guard let index = recipe.nodes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        let kept = recipe.nodes[index]
        recipe.nodes[index] = ColorNode(id: kept.id, name: kept.name, isEnabled: kept.isEnabled)
        markEdited()
        applyVideoTier()
    }

    /// Undoing the camera's encoding. Structural for the look but not for the
    /// composition, so it rides the same `videoComposition` rebuild tier as
    /// filters and adjustments — no full rebuild, playback uninterrupted.
    func setInputTransform(_ transform: VideoInputTransform) {
        guard recipe.inputTransform != transform else { return }
        pushUndo()
        recipe.inputTransform = transform
        markEdited()
        applyVideoTier()
    }

    func setGradingWheel(_ region: ColorGradingRegion, hue: Double, saturation: Double) {
        activeNode.color.grading[region].hue = hue
        activeNode.color.grading[region].saturation = saturation
        markEdited()
        applyVideoTier()
    }

    func setGradingLuminance(_ region: ColorGradingRegion, _ value: Double) {
        activeNode.color.grading[region].luminance = value
        markEdited()
        applyVideoTier()
    }

    func resetGrading(_ region: ColorGradingRegion) {
        pushUndo()
        activeNode.color.grading[region] = ColorGradingAdjustments.Wheel()
        markEdited()
        applyVideoTier()
    }

    func setMixer(_ band: ColorMixerBand, _ property: ColorMixerProperty, _ value: Double) {
        activeNode.color.mixer[band][property] = value
        markEdited()
        applyVideoTier()
    }

    func resetMixerBand(_ band: ColorMixerBand) {
        pushUndo()
        activeNode.color.mixer[band] = .identity
        markEdited()
        applyVideoTier()
    }

    /// Replaces one channel's curve wholesale — the plot hands back the whole
    /// point list after every drag, which is also what makes one undo step
    /// per gesture the right granularity.
    func setCurve(_ channel: ToneCurveChannel, points: [CurvePoint]) {
        activeNode.curve[channel] = points
        markEdited()
        applyVideoTier()
    }

    func resetCurve(_ channel: ToneCurveChannel) {
        pushUndo()
        activeNode.curve[channel] = ToneCurveAdjustments.linear
        markEdited()
        applyVideoTier()
    }

    // MARK: Imported LUT

    /// Grades through an imported `.cube`, or clears it when `nil`.
    func setLUT(_ reference: VideoLUTReference?) {
        guard recipe.lut != reference else { return }
        pushUndo()
        recipe.lut = reference
        markEdited()
        applyVideoTier()
    }

    /// How much of the LUT to mix in. No undo push per tick — the slider is
    /// one continuous gesture and one step of undo, like the grading wheels.
    func setLUTIntensity(_ value: Double) {
        guard recipe.lut != nil else { return }
        recipe.lut?.intensity = min(1, max(0, value))
        markEdited()
        applyVideoTier()
    }

    // MARK: Power windows and qualifiers

    /// Which window the Color panel is editing.
    var selectedMaskID: UUID?

    /// Windows belong to the node they limit, so this is the active node's.
    var selectedMask: PhotoMask? {
        activeNode.masks.first { $0.id == selectedMaskID }
    }

    func addMask(_ kind: PhotoMaskComponentKind) {
        guard VideoMaskRenderer.supportedKinds.contains(kind) else { return }
        pushUndo()
        let mask = PhotoMask(
            name: kind.displayName,
            component: PhotoMaskComponent(kind: kind)
        )
        activeNode.masks.append(mask)
        selectedMaskID = mask.id
        markEdited()
        applyVideoTier()
    }

    func removeMask(_ id: UUID) {
        guard activeNode.masks.contains(where: { $0.id == id }) else { return }
        pushUndo()
        activeNode.masks.removeAll { $0.id == id }
        if selectedMaskID == id { selectedMaskID = activeNode.masks.last?.id }
        markEdited()
        applyVideoTier()
    }

    func toggleMaskVisible(_ id: UUID) {
        guard let index = activeNode.masks.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        activeNode.masks[index].isVisible.toggle()
        markEdited()
        applyVideoTier()
    }

    func toggleMaskInverted(_ id: UUID) {
        guard let index = activeNode.masks.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        activeNode.masks[index].isInverted.toggle()
        markEdited()
        applyVideoTier()
    }

    /// Edits the window's first component — the panel offers one shape per
    /// window, which keeps "what am I dragging" answerable.
    func updateSelectedMaskComponent(_ mutate: (inout PhotoMaskComponent) -> Void) {
        guard let id = selectedMaskID,
              let index = activeNode.masks.firstIndex(where: { $0.id == id }),
              !activeNode.masks[index].components.isEmpty
        else { return }
        var node = activeNode
        mutate(&node.masks[index].components[0])
        activeNode = node
        markEdited()
        applyVideoTier()
    }

    func updateSelectedMaskAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        guard let id = selectedMaskID,
              let index = activeNode.masks.firstIndex(where: { $0.id == id })
        else { return }
        activeNode.masks[index].adjustments[kind] = value
        markEdited()
        applyVideoTier()
    }

    // MARK: Tracking a window

    /// Which window is being tracked and how far it has got, 0…1. Nil when
    /// nothing is tracking — the panel shows a button, then a bar.
    private(set) var trackingMaskID: UUID?
    private(set) var trackingProgress: Double = 0

    private let tracker = VideoMaskTracker()
    private var trackingTask: Task<Void, Never>?

    /// Whether this window can be followed at all. Qualifiers select by
    /// value, not by place, so there is nothing to follow.
    func canTrack(_ mask: PhotoMask) -> Bool {
        guard let component = mask.components.first else { return false }
        guard MaskTrackMath.isTrackable(component.kind) else { return false }
        // And there has to be moving footage under the playhead. Tracking a
        // photo would run, succeed, and produce a flat track.
        guard let index = clipIndexUnderPlayhead, index < recipe.clips.count else { return false }
        return recipe.clips[index].kind == .video
    }

    /// Follows the window forward from the playhead through the clip it is
    /// over. One track per window; running it again replaces the old one.
    func trackWindow(_ maskID: UUID) {
        guard trackingMaskID == nil,
              let mask = activeNode.masks.first(where: { $0.id == maskID }),
              canTrack(mask),
              let index = clipIndexUnderPlayhead,
              index < recipe.clips.count
        else { return }

        let clip = recipe.clips[index]
        let clipStart = clipPlacements[index].start
        // From the playhead, not from the clip's head: a colourist parks on
        // the frame where the window is right and tracks forward from there.
        let intoClip = max(0, currentTime - clipStart)
        let remaining = max(0, clip.effectiveDuration - intoClip)
        guard remaining > 0.1 else { return }

        let nodeID = activeNode.id
        let canvas = recipe.canvasSize()
        trackingMaskID = maskID
        trackingProgress = 0
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let track = try await tracker.track(
                    mask: mask,
                    assetID: clip.assetID,
                    clipStart: currentTime,
                    trimStart: clip.trimStart + intoClip,
                    duration: remaining,
                    renderSize: canvas,
                    onProgress: { [weak self] value in
                        Task { @MainActor [weak self] in self?.trackingProgress = value }
                    }
                )
                await MainActor.run { [weak self] in
                    self?.finishTracking(track, nodeID: nodeID)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in self?.endTracking() }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = String(
                        localized: "Couldn't follow that window. Move the playhead to a frame where the subject is clear and try again.",
                        comment: "Video Studio colour: the window tracker did not get a usable track"
                    )
                    self?.endTracking()
                }
            }
        }
    }

    func cancelTracking() {
        trackingTask?.cancel()
        trackingTask = nil
        endTracking()
    }

    /// Throws away a window's track, putting it back where it was drawn.
    func clearTrack(_ maskID: UUID) {
        guard activeNode.tracks.contains(where: { $0.maskID == maskID }) else { return }
        pushUndo()
        activeNode.tracks.removeAll { $0.maskID == maskID }
        markEdited()
        applyVideoTier()
    }

    private func finishTracking(_ track: MaskTrack, nodeID: UUID) {
        defer { endTracking() }
        guard track.keyframes.count > 1,
              let index = recipe.nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        pushUndo()
        recipe.nodes[index].tracks.removeAll { $0.maskID == track.maskID }
        recipe.nodes[index].tracks.append(track)
        markEdited()
        applyVideoTier()
    }

    private func endTracking() {
        trackingMaskID = nil
        trackingProgress = 0
        trackingTask = nil
    }

    /// Clears the whole chain back to one empty node — "reset the grade",
    /// not "reset this node", which is `resetNode(_:)`.
    func resetColor() {
        guard recipe.hasGrade else { return }
        pushUndo()
        recipe.nodes = [ColorNode()]
        selectedNodeID = recipe.nodes.first?.id
        selectedMaskID = nil
        markEdited()
        applyVideoTier()
    }

    func setAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        activeNode.adjustments[kind] = value
        markEdited()
        applyVideoTier()
    }

    /// Per-clip effect: the instructions carry the effect from the fresh
    /// recipe, so this swaps only the video composition — timing unchanged.
    /// A clip's own fade from and to the project background. Clamped to half
    /// the clip each end so the two can never cross and leave a shot that is
    /// never fully visible.
    func setFade(_ seconds: Double, at end: ClipEnd, for clipID: UUID) {
        guard !isClipLocked(clipID),
              let index = recipe.clips.firstIndex(where: { $0.id == clipID })
        else { return }
        let limit = recipe.clips[index].maximumFade()
        let value = min(max(0, seconds), limit)
        switch end {
        case .start: recipe.clips[index].fadeIn = value
        case .end: recipe.clips[index].fadeOut = value
        }
        markEdited()
        applyVideoTier()
    }

    func setEffect(_ effect: VideoClipEffect, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        pushUndo()
        recipe.clips[index].effect = effect
        markEdited()
        applyVideoTier()
    }

    /// Opens a session for an item about to be added, *before* adding it,
    /// so ✕ takes the add back with everything else (FS-12.04 §5).
    private func beginAddSession(_ target: VideoEditSession.Target) {
        endSession()
        deselectAll()
        beginSession(target)
    }

    /// Text (FS-12.04 §3): a block reading "Text" from the playhead to the
    /// end of the video, selected, with Edit open on its words. The session
    /// starts before the block exists, so ✕ leaves no block and no step.
    @discardableResult
    func addTextBlock(font: OverlayFontChoice? = nil) -> UUID {
        var overlay = PhotoOverlay.text()
        overlay.text = String(localized: "Text", table: VideoItemTitle.table, comment: "Video Studio: a caption laid over the video")
        let choice = font ?? lastFont
        overlay.fontPostScriptName = choice.postScriptName
        overlay.fontFamilyName = choice.familyName
        beginAddSession(.overlay(overlay.id))
        pushUndo()
        recipe.overlays.append(TimedOverlay(overlay: overlay, start: max(0, min(currentTime, totalDuration))))
        selectedOverlayID = overlay.id
        inspectorTextTool = .edit
        markEdited()
        return overlay.id
    }

    /// Returns the new overlay so the caller can open the text editor on it
    /// straight away — an empty caption is never what the user wanted.
    @discardableResult
    func addTextOverlay(_ text: String, at start: Double = 0) -> PhotoOverlay {
        var overlay = PhotoOverlay.text()
        overlay.text = text
        overlay.fontPostScriptName = lastFont.postScriptName
        overlay.fontFamilyName = lastFont.familyName
        recipe.overlays.append(TimedOverlay(overlay: overlay, start: max(0, start)))
        selectOverlay(overlay.id)
        markEdited()
        return overlay
    }

    /// Overlays render through the live preview proxy, not the baked composition
    /// (see `VideoRenderRecipe.bakesOverlays`), so an overlay edit only mutates the
    /// recipe — the `@Observable` proxy repaints, no video-composition rebuild.
    func updateSelectedOverlay(_ mutate: (inout PhotoOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = recipe.overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        mutate(&recipe.overlays[index].overlay)
        markEdited()
    }

    /// Mutate the selected overlay's timing wrapper (start / duration / in-out
    /// animation). Proxy-only, like every overlay edit.
    func updateSelectedTimedOverlay(_ mutate: (inout TimedOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = recipe.overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        mutate(&recipe.overlays[index])
        markEdited()
    }

    /// Overlay visibility window. Proxy-only, like every overlay edit.
    func setOverlayTiming(start: Double, duration: Double?, forOverlay id: UUID) {
        guard !isLaneLocked(.overlay(overlayLaneAssignment[id] ?? 0)) else { return }
        guard let index = recipe.overlays.firstIndex(where: { $0.id == id }) else { return }
        recipe.overlays[index].start = min(max(0, start), totalDuration)
        recipe.overlays[index].duration = duration.map { max(0.1, $0) }
        markEdited()
    }

    // MARK: - Overlay geometry (on-canvas gestures)

    /// True while a drag / pinch / rotate on the preview canvas is in flight — one
    /// undo step spans the whole gesture rather than one per frame.
    private(set) var isOverlayGestureActive = false

    func beginOverlayGesture() {
        guard selectedOverlayID != nil, !isOverlayGestureActive else { return }
        beginUndoGroup()
        isOverlayGestureActive = true
    }

    func endOverlayGesture() {
        guard isOverlayGestureActive else { return }
        isOverlayGestureActive = false
        endUndoGroup()
    }

    func moveSelectedOverlay(toCenter center: NormalizedPoint) {
        updateSelectedOverlay { $0.center = center }
    }

    func setSelectedOverlaySize(_ size: Double) {
        updateSelectedOverlay { $0.size = size }
    }

    func setSelectedOverlayRotation(_ degrees: Double) {
        updateSelectedOverlay { $0.rotationDegrees = degrees }
    }

    /// Deletes the selected caption or sticker as one undo step and ends
    /// its session as ✓ does.
    func deleteSelectedOverlay() {
        guard let selectedOverlayID else { return }
        pushUndo()
        recipe.overlays.removeAll { $0.id == selectedOverlayID }
        clearSelection()
        markEdited()
    }

    /// Letterbox / pillarbox fill colour behind aspect-fitted frames. Rides the
    /// video-composition tier (only the instructions' render recipe changes).
    func setBackground(_ color: OverlayColor) {
        pushUndo()
        recipe.background = color
        markEdited()
        applyVideoTier()
    }

    /// Duplicate the selected overlay (text or sticker), nudged so the copy is
    /// visible, and select the copy.
    func duplicateSelectedOverlay() {
        guard let selectedOverlayID,
              let timed = recipe.overlays.first(where: { $0.id == selectedOverlayID })
        else { return }
        pushUndo()
        var overlay = timed.overlay
        overlay.id = UUID()
        overlay.center = NormalizedPoint(
            x: min(1, overlay.center.x + 0.04),
            y: min(1, overlay.center.y + 0.04)
        )
        var copy = timed
        copy.overlay = overlay
        recipe.overlays.append(copy)
        selectOverlay(overlay.id)
        markEdited()
    }

    /// Add an image sticker: the PNG is copied into the overlay-image cache and
    /// referenced by id, exactly like a signature layer.
    func addImageOverlay(pngData: Data, assetIdentifier: String?) {
        guard let id = try? overlayImages.store(pngData: pngData) else {
            errorMessage = String(localized: "Couldn't add the sticker.")
            return
        }
        let overlay = PhotoOverlay.image(id: id, assetIdentifier: assetIdentifier)
        beginAddSession(.overlay(overlay.id))
        pushUndo()
        recipe.overlays.append(TimedOverlay(overlay: overlay, start: max(0, currentTime)))
        selectedOverlayID = overlay.id
        inspectorTextTool = .transform
        markEdited()
    }

    func rememberFont(_ font: OverlayFontChoice) {
        lastFont = font
        overlayFontRecents.remember(font)
    }

    var fontRecents: [OverlayFontChoice] { overlayFontRecents.recents }

    // MARK: - Export

    func export() {
        guard exportState == .idle || isFailedExport else { return }
        player?.pause()
        isPlaying = false
        exportState = .exporting(0)
        // An export runs an AVAssetReader/Writer pump for as long as the
        // video is; if the user switches away mid-run the task is suspended
        // with the sheet still reading "Exporting… 42%" and nothing ever
        // finishes it. Hold an assertion the way the indexer does, and treat
        // its expiry as a cancel the user can see.
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "video-export") { [weak self] in
            Task { @MainActor in self?.cancelExport() }
        }
        exportTask = Task { [self] in
            defer { if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) } }
            do {
                let url = try await service.export(
                    recipe: recipe,
                    sources: sources
                ) { [weak self] progress in
                    if case .exporting = self?.exportState {
                        self?.exportState = .exporting(progress)
                    }
                }
                if let serverWorkDirectory {
                    // A server run: the file goes to the export sheet;
                    // nothing reaches Photos or Creations here.
                    let folder = serverWorkDirectory.appendingPathComponent("Compose-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent("video.\(url.pathExtension)")
                    try FileManager.default.moveItem(at: url, to: destination)
                    exportState = .idle
                    composedFile = destination
                    return
                }
                exportState = .saving
                let assetID = try await service.saveToPhotos(url: url)
                recordExport(assetID: assetID)
                savedAssetID = assetID
                exportState = .idle
                onSaved?(assetID)
            } catch is CancellationError {
                exportState = .idle
            } catch {
                exportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    /// Marks this project's row exported, as the video just saved
    /// (FS-12.18 §2): the draft and the export are one row, so exporting —
    /// the first time or again after more edits — updates it, never adds a
    /// second. Never fails the export — the video is already in the library.
    func recordExport(assetID: String, now: Int = Int(Date.now.timeIntervalSince1970)) {
        guard let creationStore, var row = draftSnapshot() else { return }
        drafts?.cancel()
        row.assetId = assetID
        row.exportedAt = now
        row.updatedAt = now
        do {
            try creationStore.upsert(row)
        } catch {
            // Non-fatal: the video saved; only the record of how failed.
        }
    }

    /// Rough output size for the export row (`~24 MB`). A bits-per-pixel model
    /// over the render canvas plus a fixed audio allowance — an estimate, hence
    /// the `~` prefix at the call site.
    var estimatedExportBytes: Int64 {
        let size = recipe.canvasSize()
        let area = Double(size.width * size.height)
        let bitsPerSecond = area * 30 * 0.15 + 128_000
        let bytes = bitsPerSecond / 8 * max(0, totalDuration)
        return Int64(bytes)
    }

    // MARK: - Waveform

    private func musicURL(for source: MusicSource) -> URL? {
        switch source {
        case .bundled(let id): MusicTrackCatalog.track(id: id)?.url
        case .imported(let url, _): url
        }
    }

    /// Decodes one track's waveform, reusing an earlier decode of the same file.
    private func loadWaveform(for id: UUID) {
        guard let music = recipe.musicTracks.first(where: { $0.id == id }),
              let url = musicURL(for: music.source)
        else { return }
        if let cached = waveformsByURL[url.absoluteString] {
            musicWaveforms[id] = cached
            return
        }
        guard waveformTasks[id] == nil else { return }
        waveformTasks[id] = Task { [weak self] in
            let samples = await VideoWaveform.samples(from: url, buckets: 400)
            guard let self, !Task.isCancelled else { return }
            waveformsByURL[url.absoluteString] = samples
            musicWaveforms[id] = samples
            waveformTasks[id] = nil
        }
    }

    /// Re-syncs the waveform cache with the recipe — after an undo, say, where
    /// tracks can come back or disappear wholesale.
    private func reloadWaveforms() {
        let liveIDs = Set(recipe.musicTracks.map(\.id))
        for id in musicWaveforms.keys where !liveIDs.contains(id) {
            musicWaveforms[id] = nil
        }
        for id in waveformTasks.keys where !liveIDs.contains(id) {
            waveformTasks[id]?.cancel()
            waveformTasks[id] = nil
        }
        for music in recipe.musicTracks where musicWaveforms[music.id] == nil {
            loadWaveform(for: music.id)
        }
    }

    private var isFailedExport: Bool {
        if case .failed = exportState { return true }
        return false
    }

    // MARK: - Preview pipeline

    private func markEdited() { hasEdits = true }

    private func applyAudioTier() {
        guard let playerItem, let layout else { return }
        service.applyAudioMix(recipe: recipe, layout: layout, to: playerItem)
    }

    private func applyVideoTier() {
        guard let playerItem, let layout else { return }
        service.applyVideoComposition(recipe: recipe, layout: layout, to: playerItem)
    }

    /// Debounced full rebuild for structural edits: a drag over the timeline
    /// fires many changes, one composition build at the end is enough.
    private func schedulePreviewRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await rebuildPreview()
        }
    }

    private func rebuildPreview() async {
        guard !sources.isEmpty else { return }
        let resumeTime = currentTime
        let wasPlaying = isPlaying
        do {
            let build = try await service.makePreviewItem(recipe: recipe, sources: sources)
            layout = build.layout
            totalDuration = build.layout.totalDuration
            playerItem = build.playerItem
            if let player {
                player.replaceCurrentItem(with: build.playerItem)
            } else {
                let player = AVPlayer(playerItem: build.playerItem)
                player.actionAtItemEnd = .pause
                self.player = player
                attachObservers(to: player)
            }
            let target = min(resumeTime, max(0, totalDuration - 0.05))
            if target > 0 {
                // Explicit completion-handler variant: in an async context the
                // await-ing overload would otherwise win and serialize the seek.
                player?.seek(
                    to: VideoCompositionBuilder.time(target),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero,
                    completionHandler: { _ in }
                )
            }
            if wasPlaying { player?.play() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachObservers(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 3, timescale: 100),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.loopsPlayback else {
                    self.isPlaying = false
                    return
                }
                self.seek(to: 0)
                self.player?.play()
                self.isPlaying = true
            }
        }
    }

    private func detachObservers() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
