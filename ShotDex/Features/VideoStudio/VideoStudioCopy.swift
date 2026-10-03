import Foundation

/// Words the Video Studio composes in Swift. New strings of the canvas
/// rework live in their own table (`Resources/VideoStudio.xcstrings`) rather
/// than in the shared catalog, so a feature's copy travels with the feature.
enum VideoStudioCopy {
    static let table = "VideoStudio"

    /// The clips' own audio for the whole project (FS-12.04 §2) — the label of
    /// the one project-wide level, wherever it is shown.
    static var videoSound: String {
        String(localized: "Video sound", table: table, comment: "Video Studio: the clips' own audio level for the whole project")
    }

    /// FS-12.18 §6: the draft could not be written.
    static var draftSaveFailed: String {
        String(localized: "Couldn't save your video draft", table: table, comment: "Video Studio: banner and alert when the draft could not be written (disk full, database error)")
    }

    static var tryAgain: String {
        String(localized: "Try Again", table: table, comment: "Video Studio: retries writing the video draft")
    }

    static var leaveWithoutSaving: String {
        String(localized: "Leave Without Saving", table: table, comment: "Video Studio: closes the studio although the latest draft could not be written")
    }

    static var media: String {
        String(localized: "Media", table: table, comment: "Video Studio: the bottom-row tool that adds photos and videos to the timeline")
    }

    static var look: String {
        String(localized: "Look", table: table, comment: "Video Studio: the bottom-row tool that changes the whole video's look — filter, adjustments, colour")
    }

    static var videoSettings: String {
        String(localized: "Video Settings", table: table, comment: "Video Studio: the panel for the project's ratio, background, resolution and frame rate")
    }

    static var videoSoundCaption: String {
        String(localized: "Original clip audio, whole project", table: table, comment: "Video Studio Music panel: caption under the Video sound slider")
    }

    static var myMusic: String {
        String(localized: "MY MUSIC", table: table, comment: "Video Studio Music panel: header over the user's imported songs")
    }

    static var addMusic: String {
        String(localized: "Add Music", table: table, comment: "Video Studio: title of the Music tool's panel")
    }

    static var discardChanges: String {
        String(localized: "Discard Changes", table: table, comment: "Video Studio: the ✕ that closes a tool panel and throws away what it changed")
    }

    static var keepChanges: String {
        String(localized: "Keep Changes", table: table, comment: "Video Studio: the ✓ that ends a selection keeping what it changed")
    }

    static var trim: String {
        String(localized: "Trim", table: table, comment: "Video Studio: the command that cuts a clip's start or end")
    }

    static var duplicate: String {
        String(localized: "Duplicate", table: table, comment: "Video Studio: the command that copies the selected item right after it")
    }

    static var beats: String {
        String(localized: "Beats", table: table, comment: "Video Studio: the music command that marks a song's beats")
    }

    static var ducking: String {
        String(localized: "Ducking", table: table, comment: "Video Studio: the music command that lowers music under speech")
    }

    static var startToPlayhead: String {
        String(localized: "Start to Playhead", table: table, comment: "Video Studio Trim: cuts the selected clip's start to the playhead")
    }

    static var endToPlayhead: String {
        String(localized: "End to Playhead", table: table, comment: "Video Studio Trim: cuts the selected clip's end to the playhead")
    }

    static var dragEdgesHint: String {
        String(localized: "Or drag the clip's edges on the timeline.", table: table, comment: "Video Studio Trim: the other way to cut a clip")
    }

    static var movePlayheadIntoClip: String {
        String(localized: "Move the playhead into this clip.", table: table, comment: "Video Studio Trim: why the Start/End to Playhead chips are dimmed")
    }

    static var mute: String {
        String(localized: "Mute", table: table, comment: "Video Studio: the speaker at the head of a Volume row — silences the clip or the song, keeping its level")
    }

    static var unmute: String {
        String(localized: "Unmute", table: table, comment: "Video Studio: the speaker at the head of a Volume row — brings back the clip's or the song's level")
    }
}
