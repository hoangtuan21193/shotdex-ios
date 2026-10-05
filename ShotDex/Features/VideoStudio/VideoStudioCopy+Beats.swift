import Foundation

/// Words of the music's beats (FS-12.12): the beat card, Snap, Cut to Beat.
extension VideoStudioCopy {
    /// "96 BPM · 4/4" — always 4/4 (§2).
    static func bpmLine(_ bpm: Double) -> String {
        String(localized: "\(Int(bpm.rounded())) BPM · 4/4", table: table, comment: "Video Studio beats card: the track's tempo and its (always 4/4) time signature — 96 BPM · 4/4")
    }

    /// "30 beats marked on A1 · found on this iPhone".
    static func beatsMarked(_ count: Int, lane: String, device: String) -> String {
        String(localized: "\(count) beats marked on \(lane) · found on this \(device)", table: table, comment: "Video Studio beats card: how many beats are on the bed's lane, and that they were found on this device, not online — 30 beats marked on A1 · found on this iPhone (plural)")
    }

    static var findingBeats: String {
        String(localized: "Finding beats…", table: table, comment: "Video Studio beats card: the track is being analysed on the device")
    }

    static var noSteadyBeat: String {
        String(localized: "No steady beat", table: table, comment: "Video Studio beats card: the analysis found no tempo to snap to")
    }

    static var snapNeedsClearBeat: String {
        String(localized: "Snap needs music with a clear beat", table: table, comment: "Video Studio beats card: under No steady beat — why Snap and Cut to Beat are dimmed")
    }

    static var cantReadTrack: String {
        String(localized: "Can't read this track", table: table, comment: "Video Studio beats card: the music file could not be decoded")
    }

    static var snapClipsToBeats: String {
        String(localized: "Snap clips to beats", table: table, comment: "Video Studio beats: the switch that makes clip edges and lengths stick to the music's beats")
    }

    /// "on beat 28": a clip end standing on a beat.
    static func onBeat(_ number: Int) -> String {
        String(localized: "on beat \(number)", table: table, comment: "Video Studio beats: a clip ends on this beat — 3.30s · on beat 28")
    }

    /// "Ends on beat 28 · 0:17.50 · hold to move freely" under a snapped
    /// Duration slider.
    static func endsOnBeat(_ number: Int, at time: String) -> String {
        String(localized: "Ends on beat \(number) · \(time) · hold to move freely", table: table, comment: "Video Studio beats: under the Duration slider when the still's end sticks to a beat — which beat, when, and how to let go of it")
    }

    /// "0:17.50": a beat's time, to the hundredth.
    static func beatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return String(format: "%d:%05.2f", minutes, seconds - Double(minutes * 60))
    }

    /// "+50 ms", "0 ms", "−25 ms".
    static func offsetMilliseconds(_ value: Int) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return String(localized: "\(sign)\(abs(value)) ms", table: table, comment: "Video Studio beats: the Offset of the beat grid in milliseconds — +50 ms")
    }

    /// "Beat 14 · 0:08.75 · −0.45s": the beat an edge sticks to, when it
    /// is, and how far the edge moved to reach it.
    static func beatSnapPill(_ number: Int, at time: Double, moved: Double) -> String {
        let sign = moved >= 0 ? "+" : "−"
        let shift = String(format: "\(sign)%.2fs", abs(moved))
        return String(localized: "Beat \(number) · \(beatTime(time)) · \(shift)", table: table, comment: "Video Studio beats: the pill over the ruler while a clip edge sticks to a beat — Beat 14 · 0:08.75 · −0.45s")
    }

    static var everyBeat: String {
        String(localized: "Every Beat", table: table, comment: "Video Studio beats: snap to every beat of the bar")
    }

    static var everyBar: String {
        String(localized: "Every Bar", table: table, comment: "Video Studio beats: snap only to the first beat of each bar")
    }
}

/// Cut to Beat (FS-12.12 §6).
extension VideoStudioCopy {
    static var cutClipsToBeat: String {
        String(localized: "Cut Clips to Beat", table: table, comment: "Video Studio beats: opens the preview that moves every cut to the nearest bar")
    }

    static var cutToBeat: String {
        String(localized: "Cut to Beat", table: table, comment: "Video Studio beats: header over the Cut to Beat preview")
    }

    static var cutToBeatExplainer: String {
        String(localized: "Moves every cut to the nearest bar. Photos stretch, videos trim. One undo.", table: table, comment: "Video Studio beats: under Cut Clips to Beat — what it does")
    }

    static var photosStretchVideosTrim: String {
        String(localized: "Photos stretch, videos trim", table: table, comment: "Video Studio beats: in the Cut to Beat preview — how the clips reach their bars")
    }

    /// "4 cuts move · largest +0.8s", with "· 1 can't move" when some cannot.
    static func cutsMove(_ count: Int, largest: Double, cannotMove: Int) -> String {
        let sign = largest >= 0 ? "+" : "−"
        let shift = String(format: "\(sign)%.1fs", abs(largest))
        let moving = String(localized: "\(count) cuts move · largest \(shift)", table: table, comment: "Video Studio beats: the Cut to Beat preview's summary — how many cuts move and the largest move (plural)")
        guard cannotMove > 0 else { return moving }
        let stuck = String(localized: "\(cannotMove) can't move", table: table, comment: "Video Studio beats: in the Cut to Beat summary — cuts whose clip cannot reach its bar (plural)")
        return moving + " · " + stuck
    }

    /// "Apply to 5 Clips".
    static func applyToClips(_ count: Int) -> String {
        String(localized: "Apply to \(count) Clips", table: table, comment: "Video Studio beats: commits the Cut to Beat preview (plural)")
    }

    static func spacingTitle(_ spacing: CutToBeatMath.Spacing) -> String {
        switch spacing {
        case .everyBar: everyBar
        case .twoBars: String(localized: "2 Bars", table: table, comment: "Video Studio Cut to Beat: cuts land every second bar")
        case .fourBars: String(localized: "4 Bars", table: table, comment: "Video Studio Cut to Beat: cuts land every fourth bar")
        }
    }

    /// "−0.5s", "+0.8s": how far a cut moves.
    static func cutShift(_ seconds: Double) -> String {
        let sign = seconds >= 0 ? "+" : "−"
        return sign + String(format: "%.1fs", abs(seconds))
    }
}
