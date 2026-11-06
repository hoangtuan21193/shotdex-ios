import AVFoundation
import AVKit
import OSLog
import SwiftUI

/// FS-19.08 §6d, AC-185: the two copies of a Same video played as one. The
/// left one leads and alone has sound; the right one follows, put back on
/// the leader's time when it drifts (`CommonPhotosVideoSync`).
@MainActor
@Observable
final class MacCommonPhotosVideoPair {
    let leader: AVPlayer
    let follower: AVPlayer
    private(set) var isPlaying = false
    /// The leader's time and the length, in seconds.
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    /// AVFoundation cannot open one of the two (an AVI, a broken file).
    private(set) var cannotPlay = false
    @ObservationIgnored private var frame: Double = 1.0 / 30
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var wasPlaying = false
    /// Seeks still running: a tick then reads times from before them.
    @ObservationIgnored private var seeksInFlight = 0
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// Either side stopped short — the server went, or the file changed
    /// under a stream (§6d): said, not a frozen picture.
    @ObservationIgnored private var failureObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var infoTask: Task<Void, Never>?

    init(left: AVAsset, right: AVAsset) {
        leader = AVPlayer(playerItem: AVPlayerItem(asset: left))
        follower = AVPlayer(playerItem: AVPlayerItem(asset: right))
        follower.isMuted = true
        for player in [leader, follower] {
            player.actionAtItemEnd = .pause
            // Needed for `setRate(_:time:atHostTime:)`: both start on one clock.
            player.automaticallyWaitsToMinimizeStalling = false
        }
        // Registered on `.main`, which is the main actor's executor.
        observer = leader.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: leader.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
        for player in [leader, follower] {
            failureObservers.append(NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.failed() }
            })
        }
        infoTask = Task { [weak self, left = leader.currentItem?.asset, right = follower.currentItem?.asset] in
            guard let left, let right else { return }
            let leftPlays = (try? await left.load(.isPlayable)) == true
            let rightPlays = (try? await right.load(.isPlayable)) == true
            let playable = leftPlays && rightPlays
            let length = try? await left.load(.duration)
            let fps = try? await left.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate)
            guard let self, !Task.isCancelled else { return }
            cannotPlay = !playable
            if let length, length.seconds.isFinite { duration = length.seconds }
            if let fps { frame = CommonPhotosVideoSync.frameDuration(fps: fps) }
        }
    }

    private func tick() {
        guard !isScrubbing, seeksInFlight == 0 else { return }
        // Both read at one instant: main-queue latency is not drift.
        let now = leader.currentTime().seconds
        time = now.isFinite ? now : 0
        guard isPlaying else { return }
        // A stall in the leader holds the follower too.
        if follower.rate != leader.rate { follower.rate = leader.rate }
        let followerTime = follower.currentTime().seconds
        #if DEBUG
        // `-ShotDexCommonPhotosComparePlay`: the drift, for AC-185's proof.
        if ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosComparePlay") {
            Self.log.notice("compare video leader \(self.time, format: .fixed(precision: 3)) follower \(followerTime, format: .fixed(precision: 3)) muted \(self.follower.isMuted) leaderMuted \(self.leader.isMuted)")
        }
        #endif
        // Past the follower's own end there is nothing to put back.
        let followerEnd = follower.currentItem?.duration.seconds ?? .infinity
        if time < followerEnd, CommonPhotosVideoSync.needsSeek(leader: time, follower: followerTime, frameDuration: frame) {
            // Within a frame either side: exact seeks every tick stutter.
            let slack = CMTime(seconds: frame, preferredTimescale: 600)
            seeksInFlight += 1
            follower.seek(to: leader.currentTime(), toleranceBefore: slack, toleranceAfter: slack) { [weak self] _ in
                Task { @MainActor in self?.seeksInFlight -= 1 }
            }
        }
    }

    private func reachedEnd() {
        leader.pause()
        follower.pause()
        isPlaying = false
        if duration > 0 { time = duration }
    }

    #if DEBUG
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    /// `-ShotDexCommonPhotosComparePlay`: scrub to 60 % and play, for screenshots.
    func playFromSixTenths() {
        guard !cannotPlay else { return }
        Task { [weak self] in
            // The length is read in the background; wait for it, a little.
            for _ in 0..<50 where self?.duration == 0 { try? await Task.sleep(for: .milliseconds(100)) }
            guard let self else { return }
            scrubbing(true)
            seek(toFraction: 0.6)
            scrubbing(false)
            if !isPlaying { togglePlay() }
            Self.log.notice("compare video scrubbed to \(self.time, format: .fixed(precision: 3)) of \(self.duration, format: .fixed(precision: 3))")
        }
    }
    #endif

    func togglePlay() {
        if isPlaying {
            leader.pause()
            follower.pause()
            isPlaying = false
            return
        }
        guard !cannotPlay else { return }
        // One host time and one start for both, a moment ahead so each is
        // ready; at the end, the start is 0 (the rate call seeks there).
        let atEnd = CommonPhotosVideoSync.isAtEnd(time: time, duration: duration, frameDuration: frame)
        // `time`, not `currentTime()`: a seek just sent may not have landed.
        let start = atEnd ? CMTime.zero : CMTime(seconds: time, preferredTimescale: 600)
        if atEnd { time = 0 }
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
        leader.setRate(1, time: start, atHostTime: host)
        follower.setRate(1, time: start, atHostTime: host)
        isPlaying = true
    }

    /// The scrubber took or let go of the playhead: playback holds while it moves.
    func scrubbing(_ began: Bool) {
        if began {
            wasPlaying = isPlaying
            if isPlaying { togglePlay() }
            isScrubbing = true
        } else {
            isScrubbing = false
            seek(to: time, exact: true)
            if wasPlaying { togglePlay() }
        }
    }

    /// The scrubber: both copies to the same time. Loose while dragging,
    /// exact on release; a newer seek cancels the one still running.
    func seek(toFraction fraction: Double) {
        seek(to: CommonPhotosVideoSync.time(at: fraction, of: duration), exact: !isScrubbing)
    }

    private func seek(to seconds: Double, exact: Bool) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = exact ? CMTime.zero : CMTime(value: 1, timescale: 10)
        for player in [leader, follower] {
            seeksInFlight += 1
            player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                Task { @MainActor in self?.seeksInFlight -= 1 }
            }
        }
        time = seconds
    }

    private func failed() {
        leader.pause()
        follower.pause()
        isPlaying = false
        cannotPlay = true
    }

    /// The row changed or Compare closed: playback ends and the items go.
    func stop() {
        infoTask?.cancel()
        infoTask = nil
        if let observer { leader.removeTimeObserver(observer) }
        observer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        failureObservers.forEach { NotificationCenter.default.removeObserver($0) }
        failureObservers = []
        for player in [leader, follower] {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        isPlaying = false
    }
}

/// One copy's picture, no controls of its own: the transport below drives both.
struct MacCommonPhotosPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// One Play and one scrubber for both copies: the window's timeline, so it
/// may sit low (MAC_STYLE allows the timeline there). Its own view, so the
/// playhead's ten ticks a second redraw this row and not the window.
struct MacCommonPhotosTransport: View {
    let pair: MacCommonPhotosVideoPair

    var body: some View {
        HStack(spacing: 12) {
            // Space is handled by the window (`onKeyPress`), so a focused
            // checkbox or picker keeps its own Space.
            Button { pair.togglePlay() } label: { Image(systemName: pair.isPlaying ? "pause.fill" : "play.fill") }
                .disabled(pair.cannotPlay)
                .help(pair.isPlaying ? String(localized: "Pause (Space)", comment: "Common photos compare: video")
                                     : String(localized: "Play (Space)", comment: "Common photos compare: video"))
                .accessibilityLabel(pair.isPlaying ? String(localized: "Pause", comment: "Common photos compare: video")
                                                   : String(localized: "Play", comment: "Common photos compare: video"))
            Text(CommonPhotosVideoSync.label(pair.time)).font(.caption.monospacedDigit()).foregroundStyle(MacTheme.Editor.secondaryText)
            Slider(value: Binding(get: { pair.duration > 0 ? pair.time / pair.duration : 0 },
                                  set: { pair.seek(toFraction: $0) }),
                   onEditingChanged: { pair.scrubbing($0) })
                .accessibilityLabel(String(localized: "Playhead", comment: "Common photos compare: video scrubber"))
                .accessibilityValue(String(localized: "\(CommonPhotosVideoSync.label(pair.time)) of \(CommonPhotosVideoSync.label(pair.duration))",
                                           comment: "Common photos compare: playhead position"))
            Text(CommonPhotosVideoSync.label(pair.duration)).font(.caption.monospacedDigit()).foregroundStyle(MacTheme.Editor.secondaryText)
            Text("Sound: left", comment: "Common photos compare: only the left copy plays sound")
                .font(.caption).foregroundStyle(MacTheme.Editor.secondaryText)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(MacTheme.Editor.panel)
        .overlay(alignment: .top) { MacTheme.Editor.hairline.frame(height: 1) }
    }
}
