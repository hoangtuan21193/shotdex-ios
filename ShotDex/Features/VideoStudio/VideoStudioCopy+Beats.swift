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
}
