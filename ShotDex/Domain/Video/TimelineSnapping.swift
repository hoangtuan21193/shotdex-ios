import Foundation

/// Where a dragged time sticks (FS-12.05 §5, FS-12.12 §5): the nearest of
/// the project's edges — clip boundaries, the ends, markers, the playhead —
/// and, while a bed snaps, its beats, within a tolerance the caller turns
/// from 8pt of finger. It also says what it stuck to, for the pill that
/// names a beat.
enum TimelineSnapping {
    enum Source: Equatable, Sendable {
        case edit
        case marker
        case playhead
        case beat(BeatGrid.Tick)
    }

    struct Target: Equatable, Sendable {
        var time: Double
        var source: Source

        var beat: BeatGrid.Tick? {
            if case .beat(let tick) = source { return tick }
            return nil
        }
    }

    /// The nearest snap point to `time` within `tolerance`, or nil. Edits
    /// and beats compete on distance alone. `excluding` is where the dragged
    /// edge started — it never sticks to itself. `beats` nil, or `division`
    /// with no tick near, leaves the edits; precise trimming (FS-12.17)
    /// passes no beats at all.
    static func target(
        for time: Double,
        tolerance: Double,
        edits: [Double],
        markers: [Double] = [],
        playhead: Double? = nil,
        beats: BeatGrid? = nil,
        division: BeatGrid.Division = .beat,
        excluding: Double? = nil
    ) -> Target? {
        var candidates: [Target] = edits.map { Target(time: $0, source: .edit) }
        candidates += markers.map { Target(time: $0, source: .marker) }
        if let playhead { candidates.append(Target(time: playhead, source: .playhead)) }
        if let beats {
            let ticks = division == .bar ? beats.ticks.filter(\.isBar) : beats.ticks
            candidates += ticks.map { Target(time: $0.time, source: .beat($0)) }
        }
        if let excluding { candidates.removeAll { abs($0.time - excluding) < 0.000_1 } }
        guard let nearest = candidates.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(nearest.time - time) <= tolerance
        else { return nil }
        return nearest
    }
}
