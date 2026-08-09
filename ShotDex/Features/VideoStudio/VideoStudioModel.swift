import AVFoundation
import Photos
import SwiftUI

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

    /// The detail panel open over the bottom toolbar; nil shows the toolbar.
    enum TimelinePanel: Equatable {
        case clipEdit
        case effect
        case transition(Int)
        case text
        case filter
        case music
    }

    let mode: VideoStudioMode
    var onSaved: ((String) -> Void)?

    private let service: VideoStudioService
    let photoLibrary: PhotoLibraryService
    private let overlayFontRecents: OverlayFontRecentsStore

    var recipe: VideoProjectRecipe
    private(set) var sources: [UUID: VideoClipSource] = [:]
    private(set) var phase: Phase = .loading
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var layout: VideoCompositionBuilder.Layout?

    var activePanel: TimelinePanel?
    var selectedClipID: UUID?
    var selectedOverlayID: UUID?
    private(set) var hasEdits = false

    private(set) var currentTime: Double = 0
    private(set) var totalDuration: Double = 0
    private(set) var isPlaying = false
    var isScrubbing = false
    /// Scrub seek gate: at most one seek in flight; the newest requested time
    /// wins when the previous seek lands.
    private var isSeekInFlight = false
    private var pendingScrubTime: Double?

    private(set) var undoStack: [VideoProjectRecipe] = []
    private(set) var redoStack: [VideoProjectRecipe] = []
    private var isUndoGrouping = false

    var exportState: ExportState = .idle
    private(set) var savedAssetID: String?
    var errorMessage: String?

    var lastFont = OverlayFontChoice.system

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rebuildTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var isAudioSessionActive = false

    init(
        assets: [PHAsset],
        mode: VideoStudioMode,
        service: VideoStudioService,
        photoLibrary: PhotoLibraryService,
        overlayFontRecents: OverlayFontRecentsStore
    ) {
        self.mode = mode
        self.service = service
        self.photoLibrary = photoLibrary
        self.overlayFontRecents = overlayFontRecents
        self.recipe = VideoProjectRecipe(
            clips: assets.map { asset in
                VideoClip(
                    assetID: asset.localIdentifier,
                    kind: asset.mediaType == .video ? .video : .photo
                )
            }
        )
        recipe.syncTransitionsWithClips()
        if mode == .singleVideo {
            selectedClipID = recipe.clips.first?.id
        }
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

    // MARK: - Load

    func load() async {
        phase = .loading
        let loaded = await service.loadSources(for: recipe.clips)
        guard !loaded.sources.isEmpty else {
            phase = .failed(String(localized: "Couldn't load the selected items."))
            return
        }
        sources = loaded.sources
        // Seed video trim windows with the resolved source durations.
        for index in recipe.clips.indices {
            let clip = recipe.clips[index]
            if clip.kind == .video, let duration = loaded.durations[clip.id] {
                recipe.clips[index].sourceDuration = duration
                if recipe.clips[index].trimEnd == nil {
                    recipe.clips[index].trimEnd = duration
                }
            }
        }
        // Drop clips whose media never resolved so the timeline matches what
        // the builder will actually use.
        recipe.clips.removeAll { sources[$0.id] == nil }
        recipe.syncTransitionsWithClips()
        await rebuildPreview()
        phase = .ready
    }

    func close() {
        rebuildTask?.cancel()
        exportTask?.cancel()
        detachObservers()
        player?.pause()
        player = nil
        playerItem = nil
        if isAudioSessionActive {
            VideoAudioSession.deactivate()
            isAudioSessionActive = false
        }
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

    private static let undoDepth = 40

    /// Snapshot the recipe before a discrete mutation. Slider drags snapshot
    /// once per gesture via `beginUndoGroup`/`endUndoGroup`.
    func pushUndo() {
        guard !isUndoGrouping else { return }
        undoStack.append(recipe)
        if undoStack.count > Self.undoDepth {
            undoStack.removeFirst(undoStack.count - Self.undoDepth)
        }
        redoStack.removeAll()
    }

    func beginUndoGroup() {
        guard !isUndoGrouping else { return }
        pushUndo()
        isUndoGrouping = true
    }

    func endUndoGroup() {
        isUndoGrouping = false
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        restore(next)
    }

    private func restore(_ snapshot: VideoProjectRecipe) {
        isUndoGrouping = false
        recipe = snapshot
        if let selectedClipID, !recipe.clips.contains(where: { $0.id == selectedClipID }) {
            self.selectedClipID = nil
        }
        if let selectedOverlayID, !recipe.overlays.contains(where: { $0.id == selectedOverlayID }) {
            self.selectedOverlayID = nil
        }
        if case .transition(let index) = activePanel, !recipe.transitions.indices.contains(index) {
            activePanel = nil
        }
        markEdited()
        // Always the structural tier: a snapshot can differ in any dimension,
        // and the 300 ms debounce keeps repeated undos cheap.
        schedulePreviewRebuild()
    }

    // MARK: - Structural edits (full rebuild)

    func moveClip(from source: Int, to destination: Int) {
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
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].photoDuration = min(
            max(duration, VideoClip.photoDurationRange.lowerBound),
            VideoClip.photoDurationRange.upperBound
        )
        markEdited()
        schedulePreviewRebuild()
    }

    func setTrim(start: Double, end: Double, for clipID: UUID) {
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

    func deleteClip(_ clipID: UUID) {
        guard recipe.clips.count > 1,
              let index = recipe.clips.firstIndex(where: { $0.id == clipID })
        else { return }
        recipe.clips.remove(at: index)
        recipe.syncTransitionsWithClips()
        if selectedClipID == clipID { selectedClipID = nil }
        if case .transition(let boundary) = activePanel,
           !recipe.transitions.indices.contains(boundary) {
            activePanel = nil
        }
        markEdited()
        schedulePreviewRebuild()
    }

    func setMusic(_ selection: MusicSelection?) {
        recipe.music = selection
        markEdited()
        schedulePreviewRebuild()
    }

    func importMusic(from pickedURL: URL) {
        do {
            let copied = try service.copyImportedMusic(from: pickedURL)
            setMusic(MusicSelection(source: .imported(
                url: copied,
                displayName: pickedURL.deletingPathExtension().lastPathComponent
            )))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rotateClockwise() {
        recipe.quarterTurns = (recipe.quarterTurns + 1) % 4
        markEdited()
        schedulePreviewRebuild()
    }

    // MARK: - Audio-only edits (audioMix tier)

    func setVideoVolume(_ volume: Double) {
        recipe.videoVolume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    func setMuted(_ muted: Bool, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].isMuted = muted
        markEdited()
        applyAudioTier()
    }

    func setMusicVolume(_ volume: Double) {
        recipe.music?.volume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    func setMusicFadeIn(_ seconds: Double) {
        recipe.music?.fadeIn = max(0, seconds)
        markEdited()
        applyAudioTier()
    }

    func setMusicFadeOut(_ seconds: Double) {
        recipe.music?.fadeOut = max(0, seconds)
        markEdited()
        applyAudioTier()
    }

    // MARK: - Look edits (videoComposition tier)

    func setFilter(_ filter: PhotoFilter) {
        recipe.filter = filter
        markEdited()
        applyVideoTier()
    }

    func setFilterIntensity(_ intensity: Double) {
        recipe.filterIntensity = min(max(intensity, 0), 1)
        markEdited()
        applyVideoTier()
    }

    func setAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        recipe.adjustments[kind] = value
        markEdited()
        applyVideoTier()
    }

    /// Per-clip effect: the instructions carry the effect from the fresh
    /// recipe, so this swaps only the video composition — timing unchanged.
    func setEffect(_ effect: VideoClipEffect, for clipID: UUID) {
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return }
        recipe.clips[index].effect = effect
        markEdited()
        applyVideoTier()
    }

    func addTextOverlay(_ text: String, at start: Double = 0) {
        var overlay = PhotoOverlay.text()
        overlay.text = text
        overlay.fontPostScriptName = lastFont.postScriptName
        overlay.fontFamilyName = lastFont.familyName
        recipe.overlays.append(TimedOverlay(overlay: overlay, start: max(0, start)))
        selectedOverlayID = overlay.id
        markEdited()
        applyVideoTier()
    }

    func updateSelectedOverlay(_ mutate: (inout PhotoOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = recipe.overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        mutate(&recipe.overlays[index].overlay)
        markEdited()
        applyVideoTier()
    }

    /// Overlay visibility window — composition timing is untouched, so this
    /// rides the cheap video-composition tier too.
    func setOverlayTiming(start: Double, duration: Double?, forOverlay id: UUID) {
        guard let index = recipe.overlays.firstIndex(where: { $0.id == id }) else { return }
        recipe.overlays[index].start = min(max(0, start), totalDuration)
        recipe.overlays[index].duration = duration.map { max(0.1, $0) }
        markEdited()
        applyVideoTier()
    }

    func deleteSelectedOverlay() {
        guard let selectedOverlayID else { return }
        recipe.overlays.removeAll { $0.id == selectedOverlayID }
        self.selectedOverlayID = nil
        markEdited()
        applyVideoTier()
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
        exportTask = Task {
            do {
                let url = try await service.export(
                    recipe: recipe,
                    sources: sources
                ) { [weak self] progress in
                    if case .exporting = self?.exportState {
                        self?.exportState = .exporting(progress)
                    }
                }
                exportState = .saving
                let assetID = try await service.saveToPhotos(url: url)
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
                self?.isPlaying = false
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
