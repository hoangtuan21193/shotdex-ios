import Foundation

/// What one clip's sound holds (FS-12.13 §4), in the clip's own source
/// seconds: where the on-device classifier heard a voice, and the RMS level
/// of every 50 ms over the part that was analysed. Derived data — cached by
/// asset, never in the recipe.
struct ClipSoundActivity: Equatable, Codable, Sendable {
    struct Span: Equatable, Codable, Sendable {
        var start: Double
        var end: Double
        var duration: Double { end - start }
    }

    /// The source seconds that were analysed.
    var analyzedStart: Double
    var analyzedEnd: Double
    /// Voice segments, already without the ones shorter than 0.3 s.
    var voices: [Span]
    /// dBFS of each 50 ms window from `analyzedStart`.
    var rmsDB: [Float]

    static let rmsWindow: Double = 0.05
    /// Any Clip Sound: louder than this after the clip's level (§4).
    static let soundThresholdDB: Double = -40

    /// Whether `start…end` (source seconds) lies inside what was analysed.
    func covers(_ start: Double, _ end: Double) -> Bool {
        start >= analyzedStart - 0.001 && end <= analyzedEnd + 0.001
    }

    /// This analysis joined with one of the part just before or after it
    /// (a trim that grew): the windows run on, the voices join where they
    /// meet. `other` must start where this ends, or end where it starts.
    func joined(with other: ClipSoundActivity) -> ClipSoundActivity {
        let (first, second) = other.analyzedStart < analyzedStart ? (other, self) : (self, other)
        var voices = first.voices
        for span in second.voices {
            if let last = voices.last, span.start <= last.end + Self.rmsWindow {
                voices[voices.count - 1].end = max(last.end, span.end)
            } else {
                voices.append(span)
            }
        }
        // The first part's windows up to where the second begins.
        let kept = Int(((second.analyzedStart - first.analyzedStart) / Self.rmsWindow).rounded())
        let head = Array(first.rmsDB.prefix(kept)) + Array(repeating: Float(-120), count: max(0, kept - first.rmsDB.count))
        return ClipSoundActivity(
            analyzedStart: first.analyzedStart,
            analyzedEnd: max(first.analyzedEnd, second.analyzedEnd),
            voices: voices,
            rmsDB: head + second.rmsDB
        )
    }

    /// The parts of `start…end` this has not analysed yet, as the stretch
    /// before what was analysed and the one after it — a gap between is
    /// read too, so the analysis stays one piece. The part
    /// before starts a whole number of 50 ms windows earlier, so the
    /// windows of the two line up.
    func missing(_ start: Double, _ end: Double) -> [ClosedRange<Double>] {
        guard !covers(start, end) else { return [] }
        var parts: [ClosedRange<Double>] = []
        if start < analyzedStart - 0.001 {
            let windows = ((analyzedStart - start) / Self.rmsWindow).rounded(.up)
            parts.append(max(0, analyzedStart - windows * Self.rmsWindow)...analyzedStart)
        }
        if end > analyzedEnd + 0.001 { parts.append(analyzedEnd...end) }
        return parts
    }

    /// Any Clip Sound's spans: the 50 ms windows above −40 dBFS once the
    /// clip's own level — `gainDB`, 0 for 100 % — is applied.
    func soundSpans(gainDB: Double) -> [Span] {
        var spans: [Span] = []
        var open: Double?
        for (index, level) in rmsDB.enumerated() {
            let time = analyzedStart + Double(index) * Self.rmsWindow
            if Double(level) + gainDB > Self.soundThresholdDB {
                if open == nil { open = time }
            } else if let start = open {
                spans.append(Span(start: start, end: time))
                open = nil
            }
        }
        if let start = open {
            spans.append(Span(start: start, end: analyzedStart + Double(rmsDB.count) * Self.rmsWindow))
        }
        return spans
    }
}

/// Ducking (FS-12.13 §4): which clips trigger it, where their voices land on
/// the timeline, how the music's level runs — Volume × fade × duck — and the
/// volume ramps the one audio mix of preview and export is built from.
enum DuckingMath {
    typealias Span = ClipSoundActivity.Span

    /// One clip's triggering stretches, in timeline seconds.
    struct ClipTrigger: Equatable, Sendable {
        var clipID: UUID
        var spans: [Span]
        var seconds: Double { spans.reduce(0) { $0 + $1.duration } }
    }

    /// "Voices in 3 clips · 8.6s".
    struct Summary: Equatable, Sendable {
        var clipCount: Int
        var seconds: Double
    }

    /// Whether a clip can make the music dip: a video, with its own sound,
    /// not muted, above 0, on a V1 that is not silenced (§4).
    static func canTrigger(_ clip: VideoClip, videoVolume: Double) -> Bool {
        clip.kind == .video && !clip.isMuted && clip.volume > 0 && videoVolume > 0
    }

    /// Each triggering clip's spans on the timeline. `activity` is by
    /// asset; a clip whose asset has none — not analysed yet, or not
    /// readable — triggers nothing (§6). Source seconds become timeline
    /// seconds through the clip's trim, speed and placement, every build:
    /// reordering, trimming or a new speed reads the same analysis.
    static func triggers(
        _ recipe: VideoProjectRecipe,
        activity: [String: ClipSoundActivity],
        trigger: MusicDucking.Trigger
    ) -> [ClipTrigger] {
        let placements = placements(recipe)
        var result: [ClipTrigger] = []
        for (index, clip) in recipe.clips.enumerated() where canTrigger(clip, videoVolume: recipe.videoVolume) {
            guard let sound = activity[clip.assetID], index < placements.count else { continue }
            let source: [Span]
            switch trigger {
            case .voices:
                source = sound.voices
            case .anyClipSound:
                let gain = clip.volume * recipe.videoVolume
                source = sound.soundSpans(gainDB: 20 * log10(max(gain, 1e-6)))
            }
            let spans = timelineSpans(source, clip: clip, placement: placements[index])
            if !spans.isEmpty { result.append(ClipTrigger(clipID: clip.id, spans: spans)) }
        }
        return result
    }

    /// Source seconds → timeline seconds for one clip: what is inside its
    /// trim window, divided by its speed, from where it starts.
    static func timelineSpans(_ source: [Span], clip: VideoClip, placement: VideoTimelineMath.Placement) -> [Span] {
        let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
        let windowStart = clip.trimStart
        let windowEnd = clip.trimStart + placement.duration * speed
        return source.compactMap { span in
            let start = max(span.start, windowStart)
            let end = min(span.end, windowEnd)
            guard end > start else { return nil }
            return Span(
                start: placement.start + (start - windowStart) / speed,
                end: placement.start + (end - windowStart) / speed
            )
        }
    }

    /// The source each video asset plays, over every clip that uses it —
    /// what has to be listened to. Reordering leaves it as it is; a trim
    /// or a speed that reaches further widens it.
    static func neededRanges(_ recipe: VideoProjectRecipe) -> [String: ClosedRange<Double>] {
        var ranges: [String: ClosedRange<Double>] = [:]
        for clip in recipe.clips where clip.kind == .video {
            let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
            let start = clip.trimStart
            let end = start + clip.effectiveDuration * speed
            guard end > start else { continue }
            if let known = ranges[clip.assetID] {
                ranges[clip.assetID] = min(known.lowerBound, start)...max(known.upperBound, end)
            } else {
                ranges[clip.assetID] = start...end
            }
        }
        return ranges
    }

    static func summary(_ triggers: [ClipTrigger]) -> Summary {
        Summary(clipCount: triggers.count, seconds: triggers.reduce(0) { $0 + $1.seconds })
    }

    /// Joins spans whose silence between is shorter than `gap` — Duck in +
    /// Recover — so the music holds its floor instead of bobbing up and
    /// down between two sentences (§4).
    static func merged(_ spans: [Span], gap: Double) -> [Span] {
        let sorted = spans.sorted { $0.start < $1.start }
        var result: [Span] = []
        for span in sorted {
            if let last = result.last, span.start - last.end < gap {
                result[result.count - 1].end = max(last.end, span.end)
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// The dips of one bed: every clip's spans, merged.
    static func dips(_ triggers: [ClipTrigger], ducking: MusicDucking) -> [Span] {
        merged(triggers.flatMap(\.spans), gap: ducking.duckIn + ducking.recover)
    }

    /// The duck factor at timeline second `time`: 1 outside a dip, down to
    /// the floor over Duck in before a voice, the floor through it, back up
    /// over Recover after it. Only ever lowers.
    static func duckGain(at time: Double, dips: [Span], ducking: MusicDucking) -> Double {
        let floor = ducking.floorGain
        var gain = 1.0
        for dip in dips {
            let value: Double
            if time >= dip.start, time <= dip.end {
                value = floor
            } else if time < dip.start, time >= dip.start - ducking.duckIn {
                let progress = (dip.start - time) / ducking.duckIn
                value = floor + (1 - floor) * progress
            } else if time > dip.end, time <= dip.end + ducking.recover {
                let progress = (time - dip.end) / ducking.recover
                value = floor + (1 - floor) * progress
            } else {
                continue
            }
            gain = min(gain, value)
        }
        return gain
    }

    /// The fade factor at bed-relative second `time`, from the same ramps
    /// the mix has always used (both fades shrink together when they meet).
    static func fadeGain(at time: Double, fades: [VideoTimelineMath.VolumeRamp]) -> Double {
        for ramp in fades where time >= ramp.start - 1e-9 && time <= ramp.start + ramp.duration + 1e-9 {
            guard ramp.duration > 0 else { return ramp.toVolume }
            let progress = min(max((time - ramp.start) / ramp.duration, 0), 1)
            return ramp.fromVolume + (ramp.toVolume - ramp.fromVolume) * progress
        }
        return fades.last?.toVolume ?? 1
    }

    /// The music's level at bed-relative `time`: Volume × fade × duck.
    static func level(
        at time: Double,
        total: Double,
        volume: Double,
        fadeIn: Double,
        fadeOut: Double,
        insertAt: Double,
        dips: [Span],
        ducking: MusicDucking
    ) -> Double {
        let fades = VideoTimelineMath.musicRamps(total: total, volume: 1, fadeIn: fadeIn, fadeOut: fadeOut)
        return volume * fadeGain(at: time, fades: fades) * duckGain(at: insertAt + time, dips: dips, ducking: ducking)
    }

    /// The bed's volume ramps, relative to its own window like
    /// `VideoTimelineMath.musicRamps`. With ducking off, or nothing to dip
    /// under, they are exactly `musicRamps` — the mix is the mix it was
    /// (AC-9). Where a fade and a dip slope at once their product is not a
    /// straight line, and `setVolumeRamp` only draws straight lines, so
    /// that stretch is cut in four (D-11).
    static func ramps(
        total: Double,
        volume: Double,
        fadeIn: Double,
        fadeOut: Double,
        insertAt: Double,
        dips: [Span],
        ducking: MusicDucking
    ) -> [VideoTimelineMath.VolumeRamp] {
        let plain = VideoTimelineMath.musicRamps(total: total, volume: volume, fadeIn: fadeIn, fadeOut: fadeOut)
        let local = dips.filter { $0.end + ducking.recover > insertAt && $0.start - ducking.duckIn < insertAt + total }
        guard ducking.isOn, !local.isEmpty, total > 0 else { return plain }
        let fades = VideoTimelineMath.musicRamps(total: total, volume: 1, fadeIn: fadeIn, fadeOut: fadeOut)
        var marks: Set<Double> = [0, total]
        for ramp in fades { marks.insert(ramp.start); marks.insert(ramp.start + ramp.duration) }
        for dip in local {
            for mark in [dip.start - ducking.duckIn, dip.start, dip.end, dip.end + ducking.recover] {
                marks.insert(mark - insertAt)
            }
        }
        let points = marks.map { min(max($0, 0), total) }.sorted()
        func at(_ time: Double) -> Double {
            volume * fadeGain(at: time, fades: fades) * duckGain(at: insertAt + time, dips: local, ducking: ducking)
        }
        var ramps: [VideoTimelineMath.VolumeRamp] = []
        var previous: Double?
        for point in points {
            defer { previous = point }
            guard let start = previous, point - start > 1e-6 else { continue }
            // Straight already when the middle is the mean of the ends.
            let middle = (start + point) / 2
            let pieces = abs(at(middle) - (at(start) + at(point)) / 2) > 1e-4 ? 4 : 1
            let step = (point - start) / Double(pieces)
            for piece in 0..<pieces {
                let from = start + Double(piece) * step
                let to = piece == pieces - 1 ? point : from + step
                ramps.append(.init(start: from, duration: to - from, fromVolume: at(from), toVolume: at(to)))
            }
        }
        return ramps
    }

    /// The graph's dip below the bed's line (§3): 26pt at −12 dB, straight
    /// in dB, never below the bed's 50pt box.
    static func dipDepth(amountDB: Int, boxHeight: Double = 50) -> Double {
        min(Double(abs(amountDB)) * 26 / 12, boxHeight)
    }

    private static func placements(_ recipe: VideoProjectRecipe) -> [VideoTimelineMath.Placement] {
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: recipe.transitions.map(\.requestedOverlap), durations: durations)
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }
}
