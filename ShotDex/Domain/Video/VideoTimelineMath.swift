import Foundation

/// Pure timeline math for the Video Studio: where each clip sits, where the
/// crossfades are, how a music bed loops and ramps. Everything here works in
/// Double seconds; the composition builder converts to CMTime (timescale 600)
/// at its own boundary so instruction ranges tile exactly.
enum VideoTimelineMath {
    struct Placement: Equatable {
        var start: Double
        var duration: Double
        var end: Double { start + duration }
    }

    struct Crossfade: Equatable {
        /// Index of the outgoing clip; the incoming one is `fromIndex + 1`.
        var fromIndex: Int
        var start: Double
        var duration: Double
    }

    /// Where one trimmed music track lands under the video.
    struct MusicPlacement: Equatable {
        var insertAt: Double
        var sourceStart: Double
        var duration: Double
        var end: Double { insertAt + duration }
    }

    struct VolumeRamp: Equatable {
        var start: Double
        var duration: Double
        var fromVolume: Double
        var toVolume: Double
    }

    /// The overlaps actually used, one per boundary between adjacent clips.
    /// Clamp order per boundary `i` (between clips `i` and `i + 1`):
    ///  1. never negative,
    ///  2. at most half the shorter neighbour (a fade must not consume a clip),
    ///  3. forward pass: `overlaps[i + 1] <= durations[i + 1] - overlaps[i]`,
    ///     so a clip is never inside two fades at once — that keeps the
    ///     builder's alternating A/B tracks valid (at most two clips coexist).
    /// A `requested` count that doesn't match `durations.count - 1` is padded
    /// with zeros / truncated defensively.
    static func effectiveOverlaps(requested: [Double], durations: [Double]) -> [Double] {
        let boundaryCount = max(0, durations.count - 1)
        guard boundaryCount > 0 else { return [] }
        var overlaps = [Double](repeating: 0, count: boundaryCount)
        for index in 0..<boundaryCount {
            let wanted = index < requested.count ? max(0, requested[index]) : 0
            let limit = min(durations[index], durations[index + 1]) / 2
            overlaps[index] = min(wanted, limit)
        }
        for index in 1..<boundaryCount {
            overlaps[index] = min(overlaps[index], max(0, durations[index] - overlaps[index - 1]))
        }
        return overlaps
    }

    /// Cumulative start times: each clip starts `overlaps[i]` before the
    /// previous one ends, so neighbours coexist for that boundary's fade.
    static func placements(durations: [Double], overlaps: [Double]) -> [Placement] {
        var result: [Placement] = []
        var cursor = 0.0
        for (index, duration) in durations.enumerated() {
            result.append(Placement(start: cursor, duration: duration))
            let overlap = index < overlaps.count ? overlaps[index] : 0
            cursor += duration - overlap
        }
        return result
    }

    static func totalDuration(durations: [Double], overlaps: [Double]) -> Double {
        guard let last = placements(durations: durations, overlaps: overlaps).last else { return 0 }
        return last.end
    }

    /// The clip on top at time `t` — during a crossfade window that's the
    /// incoming clip, matching what the viewer perceives. Later clips win.
    static func clipIndex(at time: Double, placements: [Placement]) -> Int? {
        guard time >= 0 else { return nil }
        var found: Int?
        for (index, placement) in placements.enumerated()
        where time >= placement.start && time <= placement.end {
            found = index
        }
        return found
    }

    /// Every fade window between adjacent placements. `fromIndex` doubles as
    /// the boundary index, so callers can zip it with the recipe's
    /// per-boundary transitions. Windows never overlap each other because
    /// `effectiveOverlaps` caps at half a clip and forward-clamps neighbours.
    static func crossfades(placements: [Placement], overlaps: [Double]) -> [Crossfade] {
        guard placements.count >= 2 else { return [] }
        var result: [Crossfade] = []
        for index in 0..<(placements.count - 1) {
            let overlap = index < overlaps.count ? overlaps[index] : 0
            guard overlap > 0 else { continue }
            let start = placements[index + 1].start
            let duration = min(overlap, placements[index].end - start)
            guard duration > 0 else { continue }
            result.append(Crossfade(fromIndex: index, start: start, duration: duration))
        }
        return result
    }

    /// Where a music track's trimmed window sits under the video. Returns nil
    /// when the track starts at or past the end of the video, or when the trim
    /// window has nothing left to play — the builder skips those tracks
    /// entirely rather than inserting an empty range.
    static func musicPlacement(
        start: Double,
        trimStart: Double,
        trimEnd: Double?,
        sourceDuration: Double?,
        totalDuration: Double
    ) -> MusicPlacement? {
        guard let sourceDuration, sourceDuration > 0, totalDuration > 0 else { return nil }
        let insertAt = max(0, start)
        guard insertAt < totalDuration - minimumMusicDuration else { return nil }
        let sourceStart = min(max(0, trimStart), sourceDuration)
        let sourceEnd = min(max(trimEnd ?? sourceDuration, sourceStart), sourceDuration)
        let trimmed = sourceEnd - sourceStart
        guard trimmed >= minimumMusicDuration else { return nil }
        let duration = min(trimmed, totalDuration - insertAt)
        guard duration >= minimumMusicDuration else { return nil }
        return MusicPlacement(insertAt: insertAt, sourceStart: sourceStart, duration: duration)
    }

    /// Shortest music window worth inserting; below this the track is dropped.
    static let minimumMusicDuration: Double = 0.1

    /// Fade-in and fade-out ramps for one music track, in times relative to the
    /// track's own placed window (the builder offsets them by `insertAt`). When
    /// the two fades would overlap (fadeIn + fadeOut > total) both shrink
    /// proportionally so the volume envelope stays continuous.
    static func musicRamps(
        total: Double,
        volume: Double,
        fadeIn: Double,
        fadeOut: Double
    ) -> [VolumeRamp] {
        guard total > 0 else { return [] }
        var inDuration = max(0, fadeIn)
        var outDuration = max(0, fadeOut)
        let combined = inDuration + outDuration
        if combined > total, combined > 0 {
            let scale = total / combined
            inDuration *= scale
            outDuration *= scale
        }
        var ramps: [VolumeRamp] = []
        if inDuration > 0 {
            ramps.append(VolumeRamp(start: 0, duration: inDuration, fromVolume: 0, toVolume: volume))
        }
        let steadyStart = inDuration
        let steadyEnd = total - outDuration
        if steadyEnd > steadyStart {
            ramps.append(VolumeRamp(
                start: steadyStart,
                duration: steadyEnd - steadyStart,
                fromVolume: volume,
                toVolume: volume
            ))
        }
        if outDuration > 0 {
            ramps.append(VolumeRamp(
                start: steadyEnd,
                duration: outDuration,
                fromVolume: volume,
                toVolume: 0
            ))
        }
        return ramps
    }

    /// Trim clamped into the source with a minimum playable length.
    static func clampedTrim(
        start: Double,
        end: Double,
        sourceDuration: Double
    ) -> (start: Double, end: Double) {
        guard sourceDuration > 0 else { return (0, VideoClip.minimumClipDuration) }
        let minimum = min(VideoClip.minimumClipDuration, sourceDuration)
        var clampedStart = min(max(start, 0), sourceDuration - minimum)
        var clampedEnd = min(max(end, minimum), sourceDuration)
        if clampedEnd - clampedStart < minimum {
            // Prefer keeping the start; pull the end out, or the start back at
            // the source's tail.
            if clampedStart + minimum <= sourceDuration {
                clampedEnd = clampedStart + minimum
            } else {
                clampedEnd = sourceDuration
                clampedStart = sourceDuration - minimum
            }
        }
        return (clampedStart, clampedEnd)
    }

    /// 0…1 progress inside a fade window; 0 before, 1 after — drives the
    /// compositor's dissolve.
    static func fadeProgress(at time: Double, fadeStart: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= fadeStart ? 1 : 0 }
        return min(max((time - fadeStart) / duration, 0), 1)
    }

    /// Reorder drop index for the timeline strip: given the dragged tile's
    /// centre x offset within the strip and every tile's width, where does it
    /// land? Clamped to the array's bounds.
    static func dropIndex(forOffset offset: Double, widths: [Double]) -> Int {
        guard !widths.isEmpty else { return 0 }
        var edge = 0.0
        for (index, width) in widths.enumerated() {
            edge += width
            if offset < edge - width / 2 {
                return index
            }
        }
        return widths.count - 1
    }
}
