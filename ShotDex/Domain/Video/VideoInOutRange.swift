import Foundation

/// The In–Out range (FS-12.17b §5): two optional times on the ruler that
/// say where the user is watching — Loop plays inside them, Go to Start and
/// Go to End jump to them. Never a cut: the export and every lane ignore
/// it. Pinned to the ruler like a marker, so deleting a clip does not drag
/// it along.
struct VideoInOutRange: Equatable, Sendable {
    var inPoint: Double?
    var outPoint: Double?

    var isEmpty: Bool { inPoint == nil && outPoint == nil }

    /// I at `time`: In moves there; an Out at or before it is cleared.
    func markingIn(at time: Double, totalDuration: Double) -> VideoInOutRange {
        let time = Self.clamped(time, totalDuration)
        var range = self
        range.inPoint = time
        if let out = outPoint, out <= time { range.outPoint = nil }
        return range
    }

    /// O at `time`: Out moves there; an In at or after it goes back to 0.
    func markingOut(at time: Double, totalDuration: Double) -> VideoInOutRange {
        let time = Self.clamped(time, totalDuration)
        var range = self
        range.outPoint = time
        if let `in` = inPoint, `in` >= time { range.inPoint = 0 }
        return range
    }

    /// Go to Start — the transport's button and Home (§5): In, or 0 when
    /// there is no In (only an Out set, or nothing).
    var goToStartTarget: Double { inPoint ?? 0 }

    /// Go to End — the button and End: Out, or the project's end when there
    /// is no Out (only an In set, or nothing).
    func goToEndTarget(totalDuration: Double) -> Double { outPoint ?? totalDuration }

    /// Where Loop plays from: In, or the project's start.
    var loopStart: Double { inPoint ?? 0 }

    /// Where Loop turns back: Out, or the project's end.
    func loopEnd(totalDuration: Double) -> Double { outPoint ?? totalDuration }

    /// Play pressed with Loop on: from where the playhead is when it is
    /// inside the range, from In when it is outside it or at Out.
    func loopPlayStart(from time: Double, totalDuration: Double) -> Double {
        let end = loopEnd(totalDuration: totalDuration)
        if time < loopStart || time >= end - 0.05 { return loopStart }
        return time
    }

    private static func clamped(_ time: Double, _ total: Double) -> Double {
        guard time.isFinite else { return 0 }
        return min(max(0, time), max(0, total))
    }
}
