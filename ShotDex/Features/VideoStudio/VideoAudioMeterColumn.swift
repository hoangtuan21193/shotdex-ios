import AVFoundation
import Observation
import SwiftUI

/// The program level meter that stands beside the viewer on a desk-shaped
/// window, the way Resolve, Final Cut and LumaFusion all put one there.
///
/// **What it measures.** Not the audio leaving the device — `AVPlayer` hands
/// out no metering — but the project's own mix at the playhead: each clip's
/// and each music track's decoded peak envelope, scaled by the volume, mute
/// and fade the recipe asks for, summed in power and converted to dBFS. That
/// is the level the export will write, which is the number a meter is
/// consulted for, and it reads correctly while paused and while scrubbing,
/// where a playback tap would read nothing at all.
@MainActor
@Observable
final class VideoLevelMeterModel {
    /// Current level per channel, in dBFS. `Self.floor` is silence.
    private(set) var left: Double = floorDB
    private(set) var right: Double = floorDB
    /// The highest level in the last `peakWindow` seconds of the timeline —
    /// the tick that hangs above the bar.
    private(set) var peakLeft: Double = floorDB
    private(set) var peakRight: Double = floorDB

    /// Bottom of the scale. Below this the bar is empty.
    static let floorDB: Double = -54
    /// Where the bar turns from green to yellow, and from yellow to red. The
    /// same two landmarks Resolve marks: -18 dBFS is broadcast reference and
    /// -6 is the last stop before the ceiling.
    static let cautionDB: Double = -18
    static let hotDB: Double = -6

    /// How far back the peak tick looks. Long enough to be readable at 30fps,
    /// short enough to follow a cut.
    private static let peakWindow: Double = 1.2
    private static let peakStep: Double = 0.06
    private static let buckets = 600

    private var clipEnvelopes: [UUID: VideoAudioEnvelope.Samples] = [:]
    /// Music is keyed by file, not by track: two tracks on the same bed share
    /// one decode.
    private var musicEnvelopes: [URL: VideoAudioEnvelope.Samples] = [:]
    private var decoding: Set<UUID> = []
    private var decodingMusic: Set<URL> = []
    private var decodeTasks: [UUID: Task<Void, Never>] = [:]
    private var musicDecodeTasks: [URL: Task<Void, Never>] = [:]

    /// Cancelled by the screen on the way out. There is no `deinit` hook for
    /// it: the tasks hold `self` weakly and the dictionary is main-actor
    /// state, which a nonisolated `deinit` cannot touch.
    func cancelDecoding() {
        for task in decodeTasks.values { task.cancel() }
        for task in musicDecodeTasks.values { task.cancel() }
        decodeTasks.removeAll()
        musicDecodeTasks.removeAll()
        decoding.removeAll()
        decodingMusic.removeAll()
    }

    /// Recomputes the bars for the playhead's current position. Called from
    /// the view whenever the time, the recipe or the mute state changes.
    func refresh(_ model: VideoStudioModel) {
        startDecodingIfNeeded(model)
        // Read once and pass down: `clipPlacements` walks every clip to build
        // the list, and the peak window asks for twenty more samples — at 30
        // callbacks a second that is the difference between a meter and a
        // frame budget.
        let placements = model.clipPlacements
        let now = amplitudes(at: model.currentTime, model: model, placements: placements)
        left = decibels(now.left)
        right = decibels(now.right)

        var holdLeft = now.left
        var holdRight = now.right
        var offset = Self.peakStep
        while offset <= Self.peakWindow {
            let past = model.currentTime - offset
            guard past >= 0 else { break }
            let sample = amplitudes(at: past, model: model, placements: placements)
            holdLeft = max(holdLeft, sample.left)
            holdRight = max(holdRight, sample.right)
            offset += Self.peakStep
        }
        peakLeft = decibels(holdLeft)
        peakRight = decibels(holdRight)
    }

    /// Linear amplitude per channel at one timeline second, 0…1+ (a mix can
    /// sum past 1, which is exactly the clipping the red zone is there for).
    private func amplitudes(
        at seconds: Double,
        model: VideoStudioModel,
        placements: [VideoTimelineMath.Placement]
    ) -> (left: Double, right: Double) {
        let recipe = model.recipe
        let master = max(0, recipe.masterVolume)
        guard master > 0 else { return (0, 0) }
        var powerLeft = 0.0
        var powerRight = 0.0

        for (index, placement) in placements.enumerated() where
            seconds >= placement.start && seconds < placement.end {
            guard index < recipe.clips.count else { continue }
            let clip = recipe.clips[index]
            guard clip.kind == .video, !clip.isMuted,
                  let envelope = clipEnvelopes[clip.id]
            else { continue }
            let sourceTime = clip.trimStart + (seconds - placement.start) * max(clip.speed, 0.01)
            let peak = envelope.peak(atSourceSeconds: sourceTime)
            let gain = recipe.videoVolume * master
            powerLeft += pow(Double(peak.left) * gain, 2)
            powerRight += pow(Double(peak.right) * gain, 2)
        }

        for music in recipe.musicTracks {
            guard let placement = VideoTimelineMath.musicPlacement(
                start: music.start,
                trimStart: music.trimStart,
                trimEnd: music.trimEnd,
                sourceDuration: music.sourceDuration,
                totalDuration: model.totalDuration
            ), seconds >= placement.insertAt, seconds < placement.end,
               let url = Self.url(for: music.source),
               let envelope = musicEnvelopes[url]
            else { continue }
            let intoTrack = seconds - placement.insertAt
            // The meter reads the music's **own** envelope, not the waveform
            // the timeline band draws: that one is peak-normalized to fill a
            // 52pt lane, so a quiet bed and a loud one draw the same and a
            // meter fed from it would report the same level for both.
            let peak = envelope.peak(atSourceSeconds: placement.sourceStart + intoTrack)
            let gain = Self.rampedVolume(
                at: intoTrack,
                total: placement.duration,
                volume: music.volume,
                fadeIn: music.fadeIn,
                fadeOut: music.fadeOut
            ) * master
            powerLeft += pow(Double(peak.left) * gain, 2)
            powerRight += pow(Double(peak.right) * gain, 2)
        }

        return (powerLeft.squareRoot(), powerRight.squareRoot())
    }

    /// The recipe's fade envelope, read at one second into a placed track.
    /// Pure math over the same ramps the export writes, so it is `nonisolated`
    /// and testable without a main-actor hop.
    nonisolated static func rampedVolume(
        at seconds: Double,
        total: Double,
        volume: Double,
        fadeIn: Double,
        fadeOut: Double
    ) -> Double {
        let ramps = VideoTimelineMath.musicRamps(
            total: total,
            volume: volume,
            fadeIn: fadeIn,
            fadeOut: fadeOut
        )
        for ramp in ramps where seconds >= ramp.start && seconds < ramp.start + ramp.duration {
            guard ramp.duration > 0 else { return ramp.toVolume }
            let progress = (seconds - ramp.start) / ramp.duration
            return ramp.fromVolume + (ramp.toVolume - ramp.fromVolume) * progress
        }
        return volume
    }

    private func decibels(_ amplitude: Double) -> Double {
        guard amplitude > 0 else { return Self.floorDB }
        return min(0, max(Self.floorDB, 20 * log10(amplitude)))
    }

    /// Decodes the envelope of any clip that has audio and has not been
    /// measured yet. One task per clip, off the main actor, cancelled when the
    /// studio closes.
    /// Where a music bed's samples live. Bundled tracks come out of the
    /// catalog; imported ones already carry their URL.
    static func url(for source: MusicSource) -> URL? {
        switch source {
        case .bundled(let id): MusicTrackCatalog.track(id: id)?.url
        case .imported(let url, _): url
        }
    }

    private func startDecodingIfNeeded(_ model: VideoStudioModel) {
        for music in model.recipe.musicTracks {
            guard let url = Self.url(for: music.source),
                  musicEnvelopes[url] == nil,
                  !decodingMusic.contains(url)
            else { continue }
            decodingMusic.insert(url)
            musicDecodeTasks[url] = Task { [weak self] in
                let asset = AVURLAsset(url: url)
                let track = try? await asset.loadTracks(withMediaType: .audio).first
                var samples: VideoAudioEnvelope.Samples?
                if let track = track ?? nil {
                    samples = await VideoAudioEnvelope.samples(
                        for: track,
                        of: asset,
                        buckets: Self.buckets
                    )
                }
                guard let self, !Task.isCancelled else { return }
                if let samples { musicEnvelopes[url] = samples }
                decodingMusic.remove(url)
                musicDecodeTasks[url] = nil
            }
        }
        for clip in model.recipe.clips where clip.kind == .video {
            guard clipEnvelopes[clip.id] == nil, !decoding.contains(clip.id) else { continue }
            guard case .video(let asset, _, let audioTrack, _, _, _) = model.sources[clip.id],
                  let audioTrack
            else { continue }
            decoding.insert(clip.id)
            let id = clip.id
            decodeTasks[id] = Task { [weak self] in
                let samples = await VideoAudioEnvelope.samples(
                    for: audioTrack,
                    of: asset,
                    buckets: Self.buckets
                )
                guard let self, !Task.isCancelled else { return }
                if let samples { clipEnvelopes[id] = samples }
                decoding.remove(id)
                decodeTasks[id] = nil
            }
        }
    }
}

/// The meter itself: a dB scale and two channel bars, with the master mute at
/// the top — the one audio control that belongs beside the level rather than
/// three taps into an inspector.
struct VideoAudioMeterColumn: View {
    @Bindable var model: VideoStudioModel
    let meter: VideoLevelMeterModel
    let width: CGFloat

    /// The volume the mute button restores. Zero is a real setting the user
    /// can dial, so "was it muted" cannot be read off the volume alone.
    @State private var volumeBeforeMute: Double = 1

    private var isMuted: Bool { model.recipe.masterVolume <= 0 }
    private var showsScale: Bool { width >= 48 }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                if isMuted {
                    model.setMasterVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 1)
                } else {
                    volumeBeforeMute = model.recipe.masterVolume
                    model.setMasterVolume(0)
                }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMuted ? EditorTheme.timelineDestructive : .white)
                    .frame(width: width, height: 28)
                    .videoHitTarget(drawnHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isMuted
                    ? Text("Unmute Project", comment: "Video Studio level meter: restores the master volume")
                    : Text("Mute Project", comment: "Video Studio level meter: silences the whole mix")
            )

            HStack(spacing: 3) {
                if showsScale { scale }
                bar(level: meter.left, peak: meter.peakLeft)
                bar(level: meter.right, peak: meter.peakRight)
            }
            .frame(maxHeight: .infinity)

            Text(readout)
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(EditorTheme.dimText)
                .frame(height: 12)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .leading) {
            Rectangle().fill(EditorTheme.panelDivider).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Audio Levels", comment: "Video Studio: the level meter beside the viewer"))
        .accessibilityValue(Text(readout))
    }

    private var readout: String {
        let loudest = max(meter.left, meter.right)
        guard loudest > VideoLevelMeterModel.floorDB else {
            return String(localized: "—", comment: "Video Studio level meter: the mix is silent at the playhead")
        }
        return String(format: "%.0f", loudest)
    }

    /// The dB landmarks down the side. Drawn as labels pinned to their own
    /// fraction of the bar's height, so a label always sits on the level it
    /// names however tall the column is.
    private var scale: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ForEach(Self.scaleMarks, id: \.self) { mark in
                    Text("\(mark)")
                        .font(.system(size: 7.5).monospacedDigit())
                        .foregroundStyle(EditorTheme.dimText)
                        .frame(height: 8)
                        .offset(y: geo.size.height * (1 - fraction(of: Double(mark))) - 4)
                }
            }
            .frame(width: 18, alignment: .trailing)
        }
        .frame(width: 18)
    }

    private static let scaleMarks = [0, -6, -12, -18, -24, -36, -48]

    private func bar(level: Double, peak: Double) -> some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(EditorTheme.control)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Self.gradient)
                    .frame(height: height)
                    // Masked rather than shortened, so a bar's colours stay on
                    // the dB they belong to: a gradient painted into a short
                    // bar would put red at -40 whenever the mix went quiet.
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: max(0, height * fraction(of: level)))
                    }
                if peak > VideoLevelMeterModel.floorDB {
                    Rectangle()
                        .fill(peak >= VideoLevelMeterModel.hotDB ? EditorTheme.clipping : EditorTheme.meterPeak)
                        .frame(height: 1.5)
                        .offset(y: -(height * fraction(of: peak)) + 1.5)
                }
            }
        }
        .frame(width: 7)
        .animation(.linear(duration: 0.08), value: level)
    }

    private static let gradient = LinearGradient(
        stops: [
            .init(color: EditorTheme.histogramGreen, location: 0),
            .init(color: EditorTheme.histogramGreen, location: fractionOf(VideoLevelMeterModel.cautionDB)),
            .init(color: .yellow, location: fractionOf(VideoLevelMeterModel.cautionDB)),
            .init(color: .yellow, location: fractionOf(VideoLevelMeterModel.hotDB)),
            .init(color: EditorTheme.clipping, location: fractionOf(VideoLevelMeterModel.hotDB)),
            .init(color: EditorTheme.clipping, location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    private func fraction(of decibels: Double) -> CGFloat { Self.fractionOf(decibels) }

    /// dBFS to a 0…1 height. Linear in decibels, which is what every meter in
    /// every editor does — a linear-in-amplitude meter spends four fifths of
    /// its length on the top 12 dB and shows nothing below that.
    static func fractionOf(_ decibels: Double) -> CGFloat {
        let floor = VideoLevelMeterModel.floorDB
        return CGFloat(min(1, max(0, (decibels - floor) / (0 - floor))))
    }
}

/// The level meter, lying down — for the phone's Volume panel.
///
/// A desk window gives the meter its own column beside the frame, where it is
/// read while cutting. A phone has no room for a standing column, so the same
/// measurement goes where a phone user is already looking at levels: the
/// Volume panel, above the faders it is there to justify. Same numbers, same
/// scale, same colours; only the axis changes.
///
/// It keeps its own `VideoLevelMeterModel` rather than borrowing the screen's,
/// because it exists only while the panel is open — and a model threaded
/// through two call sites to be used by one of them is worse than a second
/// one that costs nothing when the panel is shut.
struct VideoLevelMeterBar: View {
    @Bindable var model: VideoStudioModel

    @State private var meter = VideoLevelMeterModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Levels", comment: "Video Studio Volume panel: the meter over the faders")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Text(readout)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(EditorTheme.dimText)
            }

            bar(level: meter.left, peak: meter.peakLeft)
            bar(level: meter.right, peak: meter.peakRight)
        }
        .padding(.horizontal, 14)
        .frame(height: VideoStudioMetrics.levelMeterBarHeight)
        .onChange(of: model.currentTime) { meter.refresh(model) }
        .onChange(of: model.recipe) { meter.refresh(model) }
        .onAppear { meter.refresh(model) }
        .onDisappear { meter.cancelDecoding() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Audio Levels", comment: "Video Studio: the level meter beside the viewer"))
        .accessibilityValue(Text(readout))
    }

    private var readout: String {
        let loudest = max(meter.left, meter.right)
        guard loudest > VideoLevelMeterModel.floorDB else {
            return String(localized: "—", comment: "Video Studio level meter: the mix is silent at the playhead")
        }
        return String(format: "%.1f dB", loudest)
    }

    private func bar(level: Double, peak: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(EditorTheme.trackChip)
                Capsule()
                    .fill(gradient)
                    .frame(width: max(0, width * fractionOf(level)))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, width * fractionOf(level)))
                    }
                // The peak hold, as a hairline where the loudest recent
                // sample was — the reading that says a transient clipped
                // even though the bar has already fallen back.
                if peak > VideoLevelMeterModel.floorDB {
                    Rectangle()
                        .fill(EditorTheme.meterPeak)
                        .frame(width: 2)
                        .offset(x: max(0, width * fractionOf(peak) - 1))
                }
            }
        }
        .frame(height: 7)
    }

    /// Full width is 0 dBFS, empty is the floor — the same mapping the
    /// standing meter uses, so a level read on a phone and on an iPad is the
    /// same level.
    private func fractionOf(_ db: Double) -> Double {
        let floor = VideoLevelMeterModel.floorDB
        guard db > floor else { return 0 }
        return min(1, (db - floor) / (0 - floor))
    }

    private var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: EditorTheme.histogramGreen, location: 0),
                .init(color: EditorTheme.histogramGreen, location: fractionOf(VideoLevelMeterModel.cautionDB)),
                .init(color: .yellow, location: fractionOf(VideoLevelMeterModel.cautionDB)),
                .init(color: .yellow, location: fractionOf(VideoLevelMeterModel.hotDB)),
                .init(color: EditorTheme.clipping, location: fractionOf(VideoLevelMeterModel.hotDB)),
                .init(color: EditorTheme.clipping, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
