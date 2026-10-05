import Foundation
import UIKit

/// Words of auto captions (FS-12.14): the row, the card, the lane, the
/// commands and their sections.
extension VideoStudioCopy {
    /// "iPhone" or "iPad" — where the recognising happens, said plainly.
    static var thisDevice: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "iPad", table: table, comment: "Video Studio captions: the device the speech is recognised on, as in Transcribing on this iPad")
            : String(localized: "iPhone", table: table, comment: "Video Studio captions: the device the speech is recognised on, as in Transcribing on this iPhone")
    }

    static var captions: String {
        String(localized: "Captions", table: table, comment: "Video Studio captions: the caption lane C1, and its name in the session footer")
    }

    static var autoCaptions: String {
        String(localized: "Auto Captions", table: table, comment: "Video Studio captions: the row under Add Text that turns speech in the clips into captions")
    }

    static var editCaptions: String {
        String(localized: "Edit Captions", table: table, comment: "Video Studio captions: the Auto Captions row once the project has a caption lane — opens it")
    }

    /// "Speech in your clips becomes editable text, made on this iPad."
    static var autoCaptionsNote: String {
        String(localized: "Speech in your clips becomes editable text, made on this \(thisDevice).", table: table, comment: "Video Studio captions: the note under Auto Captions; the argument is iPhone or iPad")
    }

    /// §8: no language can be recognised on the device at all.
    static var captionsUnavailable: String {
        String(localized: "On-device speech recognition isn't available on this \(thisDevice).", table: table, comment: "Video Studio captions: under the dimmed Auto Captions row when the device has no speech model at all")
    }

    /// "Transcribing on this iPhone…"
    static var transcribing: String {
        String(localized: "Transcribing on this \(thisDevice)…", table: table, comment: "Video Studio captions: the progress card's title while speech is recognised on the device")
    }

    /// "3 of 5 clips · nothing leaves the device".
    static func transcribingDetail(done: Int, total: Int) -> String {
        String(localized: "\(done) of \(total) clips · nothing leaves the device", table: table, comment: "Video Studio captions: under the progress bar — clips read so far, and the privacy promise")
    }

    /// The striped block on C1 over the clips still being read.
    static var transcribingBlock: String {
        String(localized: "Transcribing…", table: table, comment: "Video Studio captions: the striped block on the caption lane over the part not recognised yet")
    }

    static var speechRecognitionOff: String {
        String(localized: "Speech recognition is off for ShotDex.", table: table, comment: "Video Studio captions: the card when the speech recognition permission was refused or is restricted")
    }

    static var noSpeechFound: String {
        String(localized: "No speech found in these clips.", table: table, comment: "Video Studio captions: every clip was read and none had words")
    }

    /// "Captions stopped at 58%" — a run that ended with the studio.
    static func captionsStopped(at percent: Int) -> String {
        String(localized: "Captions stopped at \(percent)%", table: table, comment: "Video Studio captions: the card on a reopened project whose recognition was interrupted")
    }

    static var continueCaptions: String {
        String(localized: "Continue", table: table, comment: "Video Studio captions: resumes recognition with the clips not read yet")
    }

    /// "1 clip couldn't be read — it's in iCloud."
    static func clipsUnreadable(_ count: Int) -> String {
        String(localized: "\(count) clips couldn't be read — they're in iCloud.", table: table, comment: "Video Studio captions: clips skipped because their media is not on the device (plural)")
    }

    static var retry: String {
        String(localized: "Retry", table: table, comment: "Video Studio captions: reads the clips that could not be read again")
    }

    static var merge: String {
        String(localized: "Merge", table: table, comment: "Video Studio captions command: joins the selected caption with the next one")
    }

    static var language: String {
        String(localized: "Language", table: table, comment: "Video Studio captions command and row: the language the speech is recognised in")
    }

    /// "CAPTIONS · 4"
    static func captionListTitle(_ count: Int) -> String {
        String(localized: "CAPTIONS · \(count)", table: table, comment: "Video Studio captions: the header over the list of caption blocks, with how many there are")
    }

    /// "12 captions"
    static func captionCount(_ count: Int) -> String {
        String(localized: "\(count) captions", table: table, comment: "Video Studio captions: how many caption blocks the lane has (plural)")
    }

    /// "Not on this iPhone"
    static var notOnThisDevice: String {
        String(localized: "Not on this \(thisDevice)", table: table, comment: "Video Studio captions: under a language whose speech model is not on the device")
    }

    static var burnIntoVideo: String {
        String(localized: "Burn into video", table: table, comment: "Video Studio captions: the switch that draws the captions into every exported frame")
    }

    static var subtitleTrackNote: String {
        String(localized: "Saved as a subtitle track — Photos, Instagram and TikTok don't show it.", table: table, comment: "Video Studio captions: under Burn into video when it is off")
    }

    static var captionStyle: String {
        String(localized: "Style", table: table, comment: "Video Studio captions: the look of every caption in the lane")
    }

    static var captionSize: String {
        String(localized: "Size", table: table, comment: "Video Studio captions: the text height, as a share of the frame's short edge")
    }

    static var captionPosition: String {
        String(localized: "Position", table: table, comment: "Video Studio captions: where the line sits — Bottom, Middle, Top")
    }

    static func captionStyleName(_ style: CaptionStyle) -> String {
        switch style {
        case .clean: String(localized: "Clean", table: table, comment: "Video Studio caption style: white text with a shadow")
        case .box: String(localized: "Box", table: table, comment: "Video Studio caption style: white text on a dark box")
        case .outline: String(localized: "Outline", table: table, comment: "Video Studio caption style: white text with a black outline")
        case .wordByWord: String(localized: "Word by Word", table: table, comment: "Video Studio caption style: each word appears as it is said")
        }
    }

    static func captionPositionName(_ position: CaptionPosition) -> String {
        switch position {
        case .bottom: String(localized: "Bottom", table: table, comment: "Video Studio caption position")
        case .middle: String(localized: "Middle", table: table, comment: "Video Studio caption position")
        case .top: String(localized: "Top", table: table, comment: "Video Studio caption position")
        }
    }

    /// "12 captions · English (US)"
    static func captionsSummary(count: Int, language: String) -> String {
        "\(captionCount(count)) · \(language)"
    }

    static func transcribeAgainTitle(_ language: String) -> String {
        String(localized: "Transcribe again in \(language)?", table: table, comment: "Video Studio captions: asked before a language change replaces captions edited by hand")
    }

    static func transcribeAgainMessage(_ count: Int) -> String {
        String(localized: "Your \(count) edited captions will be replaced.", table: table, comment: "Video Studio captions: what a new language does to the captions edited by hand (plural)")
    }

    static var transcribe: String {
        String(localized: "Transcribe", table: table, comment: "Video Studio captions: confirms recognising the lane again in another language")
    }

    static var expandTextField: String {
        String(localized: "Expand Text Field", table: table, comment: "Video Studio captions: opens the full-screen text editor for the selected caption")
    }
}

extension VideoStudioMetrics {
    /// "0:06.0" — a caption's start or end, to the tenth.
    static func captionTime(_ seconds: Double) -> String {
        compactTimecode((max(0, seconds) * 10).rounded() / 10 + 0.000_1)
    }
}
