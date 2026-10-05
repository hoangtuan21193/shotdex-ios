import Foundation

/// Words of ducking (FS-12.13): the panel, the graph, the summary line.
extension VideoStudioCopy {
    static var underVoices: String {
        String(localized: "Under Voices", table: table, comment: "Video Studio ducking: the switch that lowers the music while the clips have someone speaking")
    }

    static var duckAmount: String {
        String(localized: "Amount", table: table, comment: "Video Studio ducking: how far the music goes down under a voice, in dB")
    }

    static var duckIn: String {
        String(localized: "Duck in", table: table, comment: "Video Studio ducking: how long the music takes to go down before a voice starts")
    }

    static var duckRecover: String {
        String(localized: "Recover", table: table, comment: "Video Studio ducking: how long the music takes to come back up after a voice ends")
    }

    static var duckUnder: String {
        String(localized: "Duck Under", table: table, comment: "Video Studio ducking: header over Voices and Any Clip Sound — what makes the music go down")
    }

    static func duckTrigger(_ trigger: MusicDucking.Trigger) -> String {
        switch trigger {
        case .voices: String(localized: "Voices", table: table, comment: "Video Studio ducking: the music goes down while someone speaks in a clip")
        case .anyClipSound: String(localized: "Any Clip Sound", table: table, comment: "Video Studio ducking: the music goes down whenever a clip has sound of its own")
        }
    }

    /// "−12 dB".
    static func decibels(_ value: Int) -> String {
        String(localized: "\(value < 0 ? "−" : "")\(abs(value)) dB", table: table, comment: "Video Studio ducking: a level in decibels, with a real minus sign — −12 dB")
    }

    /// "0.3s".
    static func duckSeconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }

    static var listeningForVoices: String {
        String(localized: "Listening for voices…", table: table, comment: "Video Studio ducking: the clips' sound is being analysed on the device; also shown while an export waits for it")
    }

    static func noVoices(_ trigger: MusicDucking.Trigger) -> String {
        switch trigger {
        case .voices: String(localized: "No voices in clip sound", table: table, comment: "Video Studio ducking: none of the clips has someone speaking")
        case .anyClipSound: String(localized: "No sound in the clips", table: table, comment: "Video Studio ducking, Any Clip Sound: none of the clips has sound loud enough to lower the music")
        }
    }

    /// "Voices in 3 clips · 8.6s".
    static func duckingSummary(_ trigger: MusicDucking.Trigger, clips: Int, seconds: Double) -> String {
        let time = String(format: "%.1fs", seconds)
        switch trigger {
        case .voices:
            return String(localized: "Voices in \(clips) clips · \(time)", table: table, comment: "Video Studio ducking: how many clips have someone speaking, and for how long in all — Voices in 3 clips · 8.6s (plural)")
        case .anyClipSound:
            return String(localized: "Sound in \(clips) clips · \(time)", table: table, comment: "Video Studio ducking, Any Clip Sound: how many clips lower the music, and for how long in all — Sound in 3 clips · 9.4s (plural)")
        }
    }

    /// " · 1 clip not checked".
    static func clipsNotChecked(_ count: Int) -> String {
        String(localized: " · \(count) clips not checked", table: table, comment: "Video Studio ducking: after the summary — clips whose sound could not be read (in iCloud with no network), so they lower nothing (plural)")
    }

    static var musicLevel: String {
        String(localized: "Music level", table: table, comment: "Video Studio ducking graph legend: the white line is the music's level")
    }

    static var onlyTheMusicMoves: String {
        String(localized: "Only the music moves. Each clip keeps its own level.", table: table, comment: "Video Studio ducking: under the settings — ducking never lowers the clips")
    }

    static var voiceLabel: String {
        String(localized: "Voice", table: table, comment: "Video Studio ducking: label on the video lane where a clip has someone speaking")
    }

    /// "A1 · music" — the graph's corner.
    static func graphLane(_ lane: String) -> String {
        String(localized: "\(lane) · music", table: table, comment: "Video Studio ducking graph: the bed it draws — A1 · music")
    }
}
