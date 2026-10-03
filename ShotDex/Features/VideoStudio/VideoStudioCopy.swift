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

    /// The Media panel's second line while nothing is selected (FS-12.09 §4).
    static func mediaTapHint(at time: String) -> String {
        String(localized: "Tap adds at \(time) · hold to drag", table: table, comment: "Video Studio Media panel: under its name — a tap inserts at the playhead time shown; holding drags onto the timeline")
    }

    /// Said after a Media cell's description when the item is already used.
    static var inThisVideo: String {
        String(localized: "in this video", table: table, comment: "Video Studio Media panel: VoiceOver, after an item that is already in the video — Video, 0:06, in this video")
    }

    /// The Media panel's tabs (FS-12.09 §3).
    static var recents: String {
        String(localized: "Recents", table: table, comment: "Video Studio Media panel tab: every photo and video, newest first")
    }

    static var albums: String {
        String(localized: "Albums", table: table, comment: "Video Studio Media panel tab: the user's albums; also the back button from an album's grid")
    }

    /// "In Video · 6": every use of a library item in this video.
    static func inVideo(_ count: Int) -> String {
        String(localized: "In Video · \(count)", table: table, comment: "Video Studio Media panel tab: what of the library is in this video, and how many uses")
    }

    static var noAlbums: String {
        String(localized: "No albums yet.", table: table, comment: "Video Studio Media panel: the Albums tab when the library has no albums of the user's own")
    }

    /// "3 selected · Add puts them at 0:08.4" (FS-12.09 §4).
    static func mediaSelectedHint(count: Int, at time: String) -> String {
        String(localized: "\(count) selected · Add puts them at \(time)", table: table, comment: "Video Studio Media panel: under its name while selecting — how many are picked and the playhead time Add inserts them at")
    }

    /// "Add (3)": inserts the picked items.
    static func addCount(_ count: Int) -> String {
        String(localized: "Add (\(count))", table: table, comment: "Video Studio Media panel: adds the picked items at the playhead, with how many")
    }

    static var select: String {
        String(localized: "Select", table: table, comment: "Video Studio Media panel: starts picking several items to add at once")
    }

    static var searchLibrary: String {
        String(localized: "Search Library", table: table, comment: "Video Studio Media panel: the search button, by camera, lens, settings or words")
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

    /// FS-12.04 §7: a clip whose original is still in iCloud.
    static var waitingForICloud: String {
        String(localized: "Waiting for iCloud", table: table, comment: "Video Studio: why Freeze and Split are dimmed on a clip whose original has not downloaded")
    }

    static func clipsWaitingForICloud(_ count: Int) -> String {
        String(localized: "\(count) clips are waiting for iCloud", table: table, comment: "Video Studio banner: clips whose originals have not downloaded yet stay in place as gaps (plural)")
    }

    /// A lane's Lock switch, named by its lane: "Lock Video", "Lock Music 2".
    static func lockLane(_ lane: String) -> String {
        String(localized: "Lock \(lane)", table: table, comment: "Video Studio track switch: stops the named lane being selected or dragged; the trait says whether it is on")
    }

    /// A lane's Mute switch: "Mute Video", "Mute Music 2".
    static func muteLane(_ lane: String) -> String {
        String(localized: "Mute \(lane)", table: table, comment: "Video Studio track switch: silences the named lane; the trait says whether it is on")
    }

    /// What the iPad's top band says about the project, which has no name
    /// (FS-12.03 §2): "5 clips · 16:9 · 0:24".
    static func projectSummary(clips: Int, ratio: String, length: String) -> String {
        let count = String(localized: "\(clips) clips", table: table, comment: "Video Projects: how many clips a video project has (plural)")
        return "\(count) · \(ratio) · \(length)"
    }

    /// "30 fps" — the project's frame rate, as the settings button prints it.
    static func framesPerSecond(_ rate: Int) -> String {
        String(localized: "\(rate) fps", table: table, comment: "Video Studio settings button: the project's frame rate, e.g. 30 fps")
    }

    /// The idle column's subtitle: the Look it shows is the whole video's,
    /// not a clip's (FS-12.03 §1).
    static var wholeVideo: String {
        String(localized: "Whole video", table: table, comment: "Video Studio: subtitle beside Look when the column shows the look of the whole video")
    }

    /// The iPad media pool's title (FS-12.03b §1).
    static var library: String {
        String(localized: "Library", table: table, comment: "Video Studio: title of the iPad's media pool column")
    }

    /// Header over the fonts the user has added captions in.
    static var fontsYouUsed: String {
        String(localized: "FONTS YOU USED", table: table, comment: "Video Studio media pool Text tab: header over the fonts the user has used before")
    }
}
