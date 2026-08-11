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

    /// Which object the inspector panel reskins for. Purely derived from the
    /// selection — there are no sheet-panels in Turn 2.
    enum InspectorTarget: Equatable {
        case none, clip, text, music
    }

    /// The no-selection inspector's sub-panel: the root (ratio / master / bg),
    /// the filter strip, or the global adjustments. Keeps Filters/Effects
    /// sheet-free — they reskin the param zone instead.
    enum NoneTool: Equatable {
        case root, filters, effects
    }

    let mode: VideoStudioMode
    var onSaved: ((String) -> Void)?

    private let service: VideoStudioService
    let photoLibrary: PhotoLibraryService
    private let overlayFontRecents: OverlayFontRecentsStore
    let overlayImages: OverlayImageStore

    var recipe: VideoProjectRecipe
    private(set) var sources: [UUID: VideoClipSource] = [:]
    private(set) var phase: Phase = .loading
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var layout: VideoCompositionBuilder.Layout?

    private(set) var selectedClipID: UUID?
    private(set) var selectedOverlayID: UUID?
    private(set) var isMusicSelected = false
    /// Set when the user taps a transition chip; drives the transition picker.
    var editingTransitionIndex: Int?
    /// The no-selection inspector's sub-panel.
    var inspectorNoneTool: NoneTool = .root
    private(set) var hasEdits = false

    /// Decoded music waveform buckets (0…1), for the audio band. Empty until a
    /// track is selected and decoded.
    private(set) var musicWaveform: [Float] = []
    private var waveformTask: Task<Void, Never>?

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
        overlayFontRecents: OverlayFontRecentsStore,
        overlayImages: OverlayImageStore
    ) {
        self.mode = mode
        self.service = service
        self.photoLibrary = photoLibrary
        self.overlayFontRecents = overlayFontRecents
        self.overlayImages = overlayImages
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

    /// Which object the inspector reskins for — selection is single-target.
    var inspectorTarget: InspectorTarget {
        if selectedOverlayID != nil { return .text }
        if selectedClipID != nil { return .clip }
        if isMusicSelected { return .music }
        return .none
    }

    // MARK: - Selection (single-target)

    func selectClip(_ id: UUID?) {
        selectedClipID = id
        if id != nil { selectedOverlayID = nil; isMusicSelected = false; inspectorNoneTool = .root }
    }

    func toggleClip(_ id: UUID) {
        selectClip(selectedClipID == id ? nil : id)
    }

    func selectOverlay(_ id: UUID?) {
        selectedOverlayID = id
        if id != nil { selectedClipID = nil; isMusicSelected = false; inspectorNoneTool = .root }
    }

    func toggleOverlay(_ id: UUID) {
        selectOverlay(selectedOverlayID == id ? nil : id)
    }

    func selectMusic() {
        guard recipe.music != nil else { return }
        isMusicSelected = true
        selectedClipID = nil
        selectedOverlayID = nil
        inspectorNoneTool = .root
    }

    func clearSelection() {
        selectedClipID = nil
        selectedOverlayID = nil
        isMusicSelected = false
        inspectorNoneTool = .root
    }

    /// Deselect everything and show a no-selection sub-panel (Filters/Effects).
    func showNoneTool(_ tool: NoneTool) {
        selectedClipID = nil
        selectedOverlayID = nil
        isMusicSelected = false
        inspectorNoneTool = tool
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
        reloadWaveform()
        await rebuildPreview()
        phase = .ready
    }

    func close() {
        rebuildTask?.cancel()
        exportTask?.cancel()
        waveformTask?.cancel()
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
        if recipe.music == nil { isMusicSelected = false }
        if let index = editingTransitionIndex, !recipe.transitions.indices.contains(index) {
            editingTransitionIndex = nil
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
        if let boundary = editingTransitionIndex,
           !recipe.transitions.indices.contains(boundary) {
            editingTransitionIndex = nil
        }
        markEdited()
        schedulePreviewRebuild()
    }

    func setMusic(_ selection: MusicSelection?) {
        recipe.music = selection
        if selection == nil { isMusicSelected = false }
        reloadWaveform()
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

    // MARK: - Structural edits (Turn 2)

    /// Output canvas shape — changes `renderSize`, so a full rebuild.
    func setAspect(_ aspect: VideoAspect) {
        guard recipe.aspect != aspect else { return }
        pushUndo()
        recipe.aspect = aspect
        markEdited()
        schedulePreviewRebuild()
    }

    func setMusicLoops(_ loops: Bool) {
        guard recipe.music != nil else { return }
        pushUndo()
        recipe.music?.loops = loops
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

    func appendMedia(_ picks: [VideoMediaPick]) {
        guard !picks.isEmpty else { return }
        let newClips = picks.map { VideoClip(assetID: $0.assetID, kind: $0.kind) }
        pushUndo()
        recipe.clips.append(contentsOf: newClips)
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
        sources.removeValue(forKey: recipe.clips[index].id)
        recipe.clips[index] = new
        recipe.syncTransitionsWithClips()
        selectClip(new.id)
        markEdited()
        Task { await loadAndMerge([new]) }
    }

    /// Loads sources for freshly-added clips and merges them in, then rebuilds.
    private func loadAndMerge(_ clips: [VideoClip]) async {
        let loaded = await service.loadSources(for: clips)
        for (id, source) in loaded.sources { sources[id] = source }
        for clip in clips where clip.kind == .video {
            guard let duration = loaded.durations[clip.id],
                  let index = recipe.clips.firstIndex(where: { $0.id == clip.id })
            else { continue }
            recipe.clips[index].sourceDuration = duration
            if recipe.clips[index].trimEnd == nil {
                recipe.clips[index].trimEnd = duration
            }
        }
        let failed = clips.filter { sources[$0.id] == nil }.map(\.id)
        if !failed.isEmpty {
            recipe.clips.removeAll { failed.contains($0.id) }
            recipe.syncTransitionsWithClips()
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

    /// Overall output gain over clip audio + music.
    func setMasterVolume(_ volume: Double) {
        recipe.masterVolume = min(max(volume, 0), 1)
        markEdited()
        applyAudioTier()
    }

    /// Hold-for-original: while true the look (filter / adjustments / overlays)
    /// is stripped from the preview via the cheap video-composition tier. Never
    /// touches the recipe, so releasing restores the edit exactly.
    func setShowsOriginal(_ value: Bool) {
        showsOriginal = value
        guard let playerItem, let layout else { return }
        var preview = recipe
        if value {
            preview.filter = .original
            preview.filterIntensity = 1
            preview.adjustments = .zero
            preview.overlays = []
        }
        service.applyVideoComposition(recipe: preview, layout: layout, to: playerItem)
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
        selectOverlay(overlay.id)
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

    /// Letterbox / pillarbox fill colour behind aspect-fitted frames. Rides the
    /// video-composition tier (only the instructions' render recipe changes).
    func setBackground(_ color: OverlayColor) {
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
        applyVideoTier()
    }

    /// Add an image sticker: the PNG is copied into the overlay-image cache and
    /// referenced by id, exactly like a signature layer.
    func addImageOverlay(pngData: Data, assetIdentifier: String?) {
        guard let id = try? overlayImages.store(pngData: pngData) else {
            errorMessage = String(localized: "Couldn't add the sticker.")
            return
        }
        let overlay = PhotoOverlay.image(id: id, assetIdentifier: assetIdentifier)
        pushUndo()
        recipe.overlays.append(TimedOverlay(overlay: overlay, start: max(0, currentTime)))
        selectOverlay(overlay.id)
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

    private func reloadWaveform() {
        waveformTask?.cancel()
        musicWaveform = []
        guard let music = recipe.music, let url = musicURL(for: music.source) else { return }
        waveformTask = Task { [weak self] in
            let samples = await VideoWaveform.samples(from: url, buckets: 400)
            if Task.isCancelled { return }
            self?.musicWaveform = samples
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
