import Foundation

/// A track's beats laid on the timeline (FS-12.12 §4–5): where each beat of
/// the analysis falls once the bed's placement, trim and Offset are
/// applied, numbered from 0 — the first beat on the timeline — and marked
/// where it starts a bar. Only beats inside the bed's trim window count:
/// "30 beats marked on A1" for 18.4s at 96 BPM.
struct BeatGrid: Equatable, Sendable {
    struct Tick: Equatable, Sendable {
        /// Timeline seconds.
        var time: Double
        /// From 0, the first beat of the bed on the timeline.
        var number: Int
        var isBar: Bool
    }

    /// What snaps (FS-12.12 §5): every beat, or only the bar's first.
    enum Division: String, Codable, CaseIterable, Sendable {
        case beat, bar
    }

    var ticks: [Tick]

    static let empty = BeatGrid(ticks: [])

    /// `start` is where the bed's audio begins on the timeline, `trimStart`
    /// … `trimEnd` the source window it plays, `offset` the user's shift of
    /// the whole grid in seconds (±0.25), `timelineEnd` the video's end.
    init(analysis: BeatAnalysis, start: Double, trimStart: Double, trimEnd: Double, offset: Double = 0, timelineEnd: Double = .infinity) {
        var ticks: [Tick] = []
        for (index, beat) in analysis.beats.enumerated() {
            let source = beat + offset
            guard source >= trimStart - 1e-9, source <= trimEnd + 1e-9 else { continue }
            let time = start + (source - trimStart)
            guard time >= -1e-9, time <= timelineEnd + 1e-9 else { continue }
            let isBar = ((index - analysis.downbeatPhase) % 4 + 4) % 4 == 0
            ticks.append(Tick(time: time, number: ticks.count, isBar: isBar))
        }
        self.ticks = ticks
    }

    init(ticks: [Tick]) {
        self.ticks = ticks
    }

    /// The ticks worth drawing at `pps`: every beat while two of them stand
    /// at least 6pt apart, only the bars when they would smear into a band.
    func visibleTicks(pointsPerSecond pps: Double) -> [Tick] {
        guard ticks.count > 1 else { return ticks }
        let spacing = (ticks[1].time - ticks[0].time) * pps
        return spacing < BeatGrid.minimumTickSpacing ? ticks.filter(\.isBar) : ticks
    }

    static let minimumTickSpacing: Double = 6

    /// The snap target nearest `time` within `tolerance` seconds, of the
    /// given division.
    func nearest(to time: Double, division: Division, tolerance: Double) -> Tick? {
        let candidates = division == .bar ? ticks.filter(\.isBar) : ticks
        guard let best = candidates.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(best.time - time) <= tolerance
        else { return nil }
        return best
    }

    /// A still's Duration on its slider (FS-12.12 §5): the length whose end
    /// lands on the nearest beat — of `division` — within `tolerance`
    /// seconds of the proposed end, or the proposed length when none is
    /// that close. Always inside `range`.
    func snappedDuration(
        _ proposed: Double,
        clipStart: Double,
        division: Division,
        tolerance: Double,
        range: ClosedRange<Double>
    ) -> (duration: Double, tick: Tick?) {
        let clamped = min(max(proposed, range.lowerBound), range.upperBound)
        guard let tick = nearest(to: clipStart + clamped, division: division, tolerance: tolerance) else {
            return (clamped, nil)
        }
        let snapped = tick.time - clipStart
        guard range.contains(snapped) else { return (clamped, nil) }
        return (snapped, tick)
    }

    /// The beat a time stands on, within a millisecond — for "on beat 28".
    func tick(at time: Double) -> Tick? {
        ticks.first { abs($0.time - time) < 0.001 }
    }
}

/// "hold to move freely" (FS-12.12 §5): a finger that stops for half a
/// second in the middle of a drag lets go of the beats until it lifts.
/// Fed every move of the drag; the pause is measured between two moves.
struct BeatSliderHold: Equatable, Sendable {
    /// How long a finger must stay still to release the snap.
    static let releaseAfter: Double = 0.5
    /// Movement under this, in points, is still "still".
    static let stillness: Double = 2

    private(set) var isFree = false
    private var anchorX: Double?
    private var anchorTime: Double = 0

    /// Records a move to `x` at `time`; returns whether the drag is free.
    mutating func update(x: Double, at time: Double) -> Bool {
        guard let anchor = anchorX else {
            anchorX = x
            anchorTime = time
            return isFree
        }
        if abs(x - anchor) >= Self.stillness {
            if time - anchorTime >= Self.releaseAfter { isFree = true }
            anchorX = x
            anchorTime = time
        }
        return isFree
    }
}
