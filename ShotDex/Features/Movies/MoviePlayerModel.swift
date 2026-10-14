import CoreGraphics
import Foundation
import Observation

/// One playback (FS-23.02): mirrors the engine's state for the screen and
/// owns the transport — chrome, touch lock, skips, speed (§3).
@MainActor
@Observable
final class MoviePlayerModel {
    static let skipMs: Int64 = 10_000
    static let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    let movie: Movie
    let player: any MoviePlaying

    private(set) var state: MoviePlaybackState = .opening
    private(set) var timeMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var audioTracks: [MovieAudioTrack] = []
    private(set) var selectedAudioTrackId: String?
    /// Audio Sync (§3b), −5000…+5000 ms; positive = sound later.
    private(set) var audioDelayMs: Int
    /// The Audio & Subtitles panel (§3b); the movie keeps playing under it.
    private(set) var isTracksPanelOpen = false

    // Subtitles (FS-23.03)
    private(set) var subtitles: [MovieSubtitle] = []
    private(set) var subtitleChoice: MovieSubtitleChoice
    private(set) var subtitleStyle: MovieSubtitleStyle
    private(set) var primaryTimeline: SubtitleTimeline?
    private(set) var secondaryTimeline: SubtitleTimeline?
    /// The time subtitles are drawn at: VLC's reports, run on between them
    /// by the host clock (§4). Read every frame, so not observed.
    @ObservationIgnored private var clock = PlaybackClock()
    private(set) var rate: Double
    private(set) var videoSize: CGSize = .zero
    private(set) var fillsFrame = false
    private(set) var canPictureInPicture = false
    private(set) var isPictureInPictureActive = false

    private(set) var isChromeVisible = true
    /// Touch lock (§3): taps only bring up the unlock button.
    private(set) var isLocked = false
    private(set) var showsUnlock = false
    /// Bumped on every touch; the screen restarts its 3 s hide timer on it.
    private(set) var interaction = 0
    /// Scrubber held: the chrome stays up and the label follows the finger.
    private(set) var scrubMs: Int64?
    /// `Resumed at 47:12 · Start Over`, for 5 s after opening (§2).
    private(set) var resumedAtMs: Int64?
    /// Where to go once the engine plays — VLC drops a seek made earlier.
    private var pendingResumeMs: Int64?
    private var lastSavedMs: Int64 = 0
    private var hasMarkedWatched = false
    private var hasStoredDuration = false
    private var hasChosenAudio = false
    private let audioLanguages: [String]
    private let subtitleLanguages: [String]
    private let subtitleLoader: MovieSubtitleLoader?
    private let rememberStyle: (MovieSubtitleStyle) -> Void
    /// The source is a Files folder: sidecars read `From Files` (03 §1).
    let sourceIsFiles: Bool
    /// When the movie time last moved — buffering reports alone do not
    /// mean the picture stopped.
    private var lastProgress = Date()

    /// Lets go of the stream's connection (FS-23.01 §3).
    private let onClose: () -> Void
    private let store: MovieStore?

    static let audioDelayLimitMs = 5_000
    static let audioDelayStepMs = 50

    init(
        movie: Movie,
        player: any MoviePlaying,
        store: MovieStore? = nil,
        audioLanguages: [String] = [],
        subtitleLanguages: [String] = [],
        subtitleLoader: MovieSubtitleLoader? = nil,
        defaultSubtitleStyle: MovieSubtitleStyle = MovieSubtitleStyle(),
        rememberStyle: @escaping (MovieSubtitleStyle) -> Void = { _ in },
        sourceIsFiles: Bool = false,
        onClose: @escaping () -> Void = {}
    ) {
        self.movie = movie
        self.player = player
        self.store = store
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.subtitleLoader = subtitleLoader
        self.rememberStyle = rememberStyle
        self.sourceIsFiles = sourceIsFiles
        self.onClose = onClose
        let choice = (try? store?.subtitleChoice(movieId: movie.id)) ?? nil
        subtitleChoice = choice ?? MovieSubtitleChoice(movieId: movie.id)
        subtitleStyle = choice.map { MovieSubtitleStyle.decode($0.style) } ?? defaultSubtitleStyle
        audioDelayMs = min(max(movie.audioDelayMs, -Self.audioDelayLimitMs), Self.audioDelayLimitMs)
        durationMs = movie.durationMs ?? 0
        rate = Self.rates.contains(movie.playbackRate) ? movie.playbackRate : 1
        pendingResumeMs = MoviePlaybackPosition.resumeMs(saved: movie.positionMs, durationMs: movie.durationMs ?? 0)
        player.onChange = { [weak self] in self?.sync() }
        sync()
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var failureReason: String? {
        if case .failed(let reason) = state { return reason }
        return nil
    }

    var isPlaying: Bool { state == .playing || state == .buffering }

    /// What the elapsed label and the scrubber show.
    var displayMs: Int64 { scrubMs ?? timeMs }

    /// The picture is wider than tall — or not decoded yet, where a movie
    /// almost always is (§4: the phone turns the frame for it).
    var isLandscapePicture: Bool {
        videoSize.width <= 0 || videoSize.width >= videoSize.height
    }

    func start() {
        VideoAudioSession.activate()
        if rate != 1 { player.rate = rate }
        if audioDelayMs != 0 { player.audioDelayMs = audioDelayMs }
        player.play()
    }

    /// Spinner: opening, or playing with the clock stuck for over a second
    /// (FS-23.02 §2 — never over a picture that moves).
    func needsSpinner(at now: Date = Date()) -> Bool {
        switch state {
        case .opening: true
        case .buffering, .playing: now.timeIntervalSince(lastProgress) > 1
        default: false
        }
    }

    func togglePlay() {
        touched()
        if isPlaying {
            player.pause()
            savePosition()
        } else {
            player.play()
        }
    }

    /// From the top, from the resume label.
    func startOver() {
        resumedAtMs = nil
        seek(toMs: 0)
        savePosition()
    }

    func dismissResumeNotice() {
        resumedAtMs = nil
    }

    // MARK: Gestures (§3)

    /// One tap on the picture: chrome on/off, or — locked — the unlock
    /// button and nothing else.
    func tapPicture() {
        if isTracksPanelOpen {
            closeTracksPanel()
            return
        }
        if isLocked {
            showsUnlock.toggle()
        } else {
            isChromeVisible.toggle()
        }
        interaction += 1
    }

    /// Double tap: −10 s on the leading half, +10 s on the trailing half.
    /// Locked, it is only a tap — a knee on the tray must not move the movie.
    func doubleTap(isLeading: Bool) {
        guard !isLocked else {
            showsUnlock = true
            interaction += 1
            return
        }
        skip(by: isLeading ? -Self.skipMs : Self.skipMs)
    }

    func skip(by deltaMs: Int64) {
        seek(toMs: timeMs + deltaMs)
    }

    func seek(toMs ms: Int64) {
        touched()
        let upper = durationMs > 0 ? durationMs : Int64.max
        let target = min(max(0, ms), upper)
        player.seek(toMs: target)
        timeMs = target
        lastProgress = Date()
        clock.seek(to: target, at: Self.hostTime)
    }

    func scrub(toMs ms: Int64) {
        scrubMs = ms
        interaction += 1
    }

    func endScrub() {
        guard let target = scrubMs else { return }
        scrubMs = nil
        seek(toMs: target)
    }

    func lock() {
        isLocked = true
        isChromeVisible = false
        showsUnlock = false
        interaction += 1
    }

    func unlock() {
        isLocked = false
        showsUnlock = false
        isChromeVisible = true
        interaction += 1
    }

    /// The 3 s timer ran out with no touch: the unlock button goes, and the
    /// chrome too while the movie plays (a paused movie keeps its controls).
    func hideAfterIdle() {
        showsUnlock = false
        guard isPlaying, scrubMs == nil else { return }
        isChromeVisible = false
    }

    /// Fit ↔ Fill (§3): the button, and a pinch out or in.
    func setFill(_ fills: Bool) {
        touched()
        guard fills != fillsFrame else { return }
        player.fillsFrame = fills
        fillsFrame = fills
    }

    func togglePictureInPicture() {
        touched()
        player.togglePictureInPicture()
    }

    /// Leaving the app (§4): the movie carries on only in picture in
    /// picture; there is no background audio.
    func enterBackground() {
        savePosition()
        guard !isPictureInPictureActive, isPlaying else { return }
        player.pause()
    }

    // MARK: Audio & Subtitles (§3b)

    func openTracksPanel() {
        isTracksPanelOpen = true
        isChromeVisible = false
    }

    func closeTracksPanel() {
        isTracksPanelOpen = false
        touched()
    }

    /// Switches without stopping: the clock carries on (AC-15). The panel
    /// stays open so the user can listen.
    func selectAudio(id: String) {
        guard id != selectedAudioTrackId else { return }
        player.selectAudioTrack(id: id)
        selectedAudioTrackId = id
        saveAudio()
    }

    func setAudioDelay(ms: Int) {
        let clamped = min(max(ms, -Self.audioDelayLimitMs), Self.audioDelayLimitMs)
        audioDelayMs = clamped
        player.audioDelayMs = clamped
        saveAudio()
    }

    func nudgeAudioDelay(by steps: Int) {
        setAudioDelay(ms: audioDelayMs + steps * Self.audioDelayStepMs)
    }

    private func saveAudio() {
        try? store?.setAudio(id: movie.id, trackId: selectedAudioTrackId, delayMs: audioDelayMs)
    }

    /// First time the tracks are known: the one picked for this movie, else
    /// the first Audio Language it has, else the file's default (§3b).
    private func chooseAudioOnce() {
        guard !hasChosenAudio, !audioTracks.isEmpty else { return }
        hasChosenAudio = true
        guard let choice = MovieTrackChoice.audioTrack(audioTracks, preferredLanguages: audioLanguages, remembered: movie.audioTrackId),
              choice.id != selectedAudioTrackId else { return }
        player.selectAudioTrack(id: choice.id)
        selectedAudioTrackId = choice.id
    }

    /// Speed, remembered per movie (§3).
    func setRate(_ newRate: Double) {
        touched()
        rate = newRate
        player.rate = newRate
        try? store?.setPlaybackRate(newRate, id: movie.id)
    }

    private func touched() {
        if !isLocked { isChromeVisible = true }
        interaction += 1
    }

    func close() {
        savePosition()
        player.close()
        VideoAudioSession.deactivate()
        onClose()
    }

    private func sync() {
        state = player.state
        let host = Self.hostTime
        if player.timeMs != timeMs {
            lastProgress = Date()
            clock.report(player.timeMs, at: host)
        }
        clock.setRunning(state == .playing, at: host)
        clock.setRate(player.rate, at: host)
        timeMs = player.timeMs
        if player.durationMs > 0 { durationMs = player.durationMs }
        audioTracks = player.audioTracks
        if player.videoSize != videoSize { videoSize = player.videoSize }
        fillsFrame = player.fillsFrame
        canPictureInPicture = player.canPictureInPicture
        isPictureInPictureActive = player.isPictureInPictureActive
        selectedAudioTrackId = player.selectedAudioTrackId
        followPlayback()
    }

    // MARK: Subtitles (FS-23.03)

    static var hostTime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The movie time to draw subtitles at, on the frame's host time.
    func subtitleTimeMs(at host: TimeInterval) -> Int64 {
        clock.timeMs(at: host)
    }

    /// Reads the movie's subtitles and the two chosen ones. A movie opened
    /// the first time starts with the first Subtitle Language it has (§2).
    func loadSubtitles() async {
        subtitles = (try? store?.subtitles(movieId: movie.id)) ?? []
        if (try? store?.subtitleChoice(movieId: movie.id)) == nil,
           let first = MovieTrackChoice.primarySubtitle(subtitles, language: \.language, preferredLanguages: subtitleLanguages) {
            subtitleChoice.primaryId = first.id
            saveChoice()
        }
        primaryTimeline = await timeline(for: subtitleChoice.primaryId)
        secondaryTimeline = await timeline(for: subtitleChoice.secondaryId)
    }

    enum SubtitleLine { case primary, secondary }

    func subtitleTitle(_ subtitle: MovieSubtitle) -> String {
        MovieSubtitleLabel.title(subtitle, fromFiles: sourceIsFiles)
    }

    func subtitle(id: String?) -> MovieSubtitle? {
        id.flatMap { id in subtitles.first { $0.id == id } }
    }

    /// Primary or Secondary from its menu (§2); nil = Off.
    func selectSubtitle(_ id: String?, for line: SubtitleLine) async {
        switch line {
        case .primary: subtitleChoice.primaryId = id
        case .secondary: subtitleChoice.secondaryId = id
        }
        saveChoice()
        let timeline = await timeline(for: id)
        switch line {
        case .primary: primaryTimeline = timeline
        case .secondary: secondaryTimeline = timeline
        }
    }

    func setSubtitlePosition(_ position: DualSubtitlePosition) {
        subtitleStyle.position = position
        saveStyle()
    }

    func setSubtitleScale(_ scale: Double, for line: SubtitleLine) {
        let clamped = min(max(scale, MovieSubtitleStyle.Line.scaleRange.lowerBound), MovieSubtitleStyle.Line.scaleRange.upperBound)
        switch line {
        case .primary: subtitleStyle.primary.scale = clamped
        case .secondary: subtitleStyle.secondary.scale = clamped
        }
        saveStyle()
    }

    func setSubtitleColor(_ color: MovieSubtitleStyle.Color, for line: SubtitleLine) {
        switch line {
        case .primary: subtitleStyle.primary.color = color
        case .secondary: subtitleStyle.secondary.color = color
        }
        saveStyle()
    }

    static let subtitleSyncLimitMs = 10_000

    /// Sync (§2): −10…+10 s in 0.1 s steps, seen at once, kept on the
    /// subtitle so it holds next time.
    func setSubtitleSync(_ ms: Int, for line: SubtitleLine) {
        let id = line == .primary ? subtitleChoice.primaryId : subtitleChoice.secondaryId
        guard let id, let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(ms, -Self.subtitleSyncLimitMs), Self.subtitleSyncLimitMs)
        subtitles[index].offsetMs = clamped
        try? store?.saveSubtitle(subtitles[index])
        switch line {
        case .primary: primaryTimeline?.delayMs = Int64(clamped)
        case .secondary: secondaryTimeline?.delayMs = Int64(clamped)
        }
        // Both lines may show the same subtitle.
        if subtitleChoice.primaryId == subtitleChoice.secondaryId {
            primaryTimeline?.delayMs = Int64(clamped)
            secondaryTimeline?.delayMs = Int64(clamped)
        }
    }

    func subtitleSyncMs(for line: SubtitleLine) -> Int {
        subtitle(id: line == .primary ? subtitleChoice.primaryId : subtitleChoice.secondaryId)?.offsetMs ?? 0
    }

    private func saveChoice() {
        subtitleChoice.style = subtitleStyle.json
        try? store?.saveSubtitleChoice(subtitleChoice)
    }

    /// Per movie, and the newest becomes the default for movies opened
    /// the first time (§2).
    private func saveStyle() {
        saveChoice()
        rememberStyle(subtitleStyle)
    }

    private func timeline(for id: String?) async -> SubtitleTimeline? {
        guard let id, let subtitle = subtitles.first(where: { $0.id == id }), let loader = subtitleLoader,
              let document = try? await loader.document(for: subtitle) else { return nil }
        return SubtitleTimeline(document: document, delayMs: Int64(subtitle.offsetMs))
    }

    // MARK: Position (§2)

    private func followPlayback() {
        if state == .playing { chooseAudioOnce() }
        if state == .playing, let target = pendingResumeMs {
            pendingResumeMs = nil
            if MoviePlaybackPosition.resumeMs(saved: target, durationMs: durationMs) != nil {
                player.seek(toMs: target)
                timeMs = target
                lastSavedMs = target
                resumedAtMs = target
                clock.seek(to: target, at: Self.hostTime)
            }
        }
        if durationMs > 0, durationMs != (movie.durationMs ?? 0), !hasStoredDuration {
            hasStoredDuration = true
            try? store?.setDuration(durationMs, id: movie.id)
        }
        if state == .ended {
            markWatched()
        } else if isPlaying, abs(timeMs - lastSavedMs) >= MoviePlaybackPosition.saveIntervalMs {
            savePosition()
        }
    }

    /// Every 10 s while playing, on pause, on close and when leaving the
    /// app. From 95% on the movie is watched and starts from the top next
    /// time.
    private func savePosition() {
        guard pendingResumeMs == nil, !hasMarkedWatched else { return }
        if MoviePlaybackPosition.isWatched(positionMs: timeMs, durationMs: durationMs) {
            markWatched()
            return
        }
        lastSavedMs = timeMs
        try? store?.recordPosition(id: movie.id, positionMs: timeMs)
    }

    private func markWatched() {
        guard !hasMarkedWatched else { return }
        hasMarkedWatched = true
        try? store?.setWatched(true, ids: [movie.id])
    }
}
