import Foundation
import ShotDexKit

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

    /// "6 items in this video": the footer while In Video is open.
    static func itemsInThisVideo(_ count: Int) -> String {
        String(localized: "\(count) items in this video", table: table, comment: "Video Studio Media panel: under its name on the In Video tab — how many uses of library items the video has")
    }

    static var nothingInVideo: String {
        String(localized: "Nothing from your library is in this video yet.", table: table, comment: "Video Studio Media panel: the In Video tab when no clip or sticker comes from the library")
    }

    /// "Photo · clip 1", "Video · clip 2", "Photo · sticker".
    static func inVideoKind(_ kind: MediaUsage.Row.Kind) -> String {
        switch kind {
        case .clip(.video, let number):
            String(localized: "Video · clip \(number)", table: table, comment: "Video Studio In Video row: a video clip and its place on the track")
        case .clip(.photo, let number):
            String(localized: "Photo · clip \(number)", table: table, comment: "Video Studio In Video row: a photo clip and its place on the track")
        case .clip(.freeze, let number):
            String(localized: "Freeze · clip \(number)", table: table, comment: "Video Studio In Video row: a held frame and its place on the track")
        case .sticker:
            String(localized: "Photo · sticker", table: table, comment: "Video Studio In Video row: a library photo laid over the video as a sticker")
        }
    }

    /// The limited-access row (FS-12.09 §4).
    static func limitedAccess(_ count: Int) -> String {
        String(localized: "ShotDex can see the \(count) items you chose.", table: table, comment: "Video Studio Media panel: with limited Photos access, how many items the user granted")
    }

    /// The one label for limited access everywhere (FS-12.09 §9).
    static var manageAccess: String {
        String(localized: "Manage Access…", table: table, comment: "Video Studio Media panel: opens the system picker to grant more photos under limited access")
    }

    static var limitedPhotosAccess: String {
        String(localized: "Limited Photos access", table: table, comment: "Video Studio Media panel: under its name when Photos access is limited")
    }

    static var noAccessToPhotos: String {
        String(localized: "No Access to Photos", table: table, comment: "Video Studio Media panel: title when Photos access is denied")
    }

    static var noAccessMessage: String {
        String(localized: "Allow access to your photo library in Settings to add photos and videos here.", table: table, comment: "Video Studio Media panel: body when Photos access is denied")
    }

    static var openSettings: String {
        String(localized: "Open Settings", table: table, comment: "Video Studio: opens the app's page in Settings")
    }

    static var noPhotosYet: String {
        String(localized: "No photos or videos yet.", table: table, comment: "Video Studio Media panel: Recents when the library is empty")
    }

    static var searchPrompt: String {
        String(localized: "Camera, lens, 85mm, ISO 3200…", table: table, comment: "Video Studio Media panel: placeholder of the search field — the Library's query language")
    }

    static var cancel: String {
        String(localized: "Cancel", table: table, comment: "Video Studio: leaves search")
    }

    static var noMatches: String {
        String(localized: "Nothing in your library matches.", table: table, comment: "Video Studio Media panel: a search that found nothing")
    }

    static var mediaDragHint: String {
        String(localized: "Drop between clips · back on the grid cancels", table: table, comment: "Video Studio Media panel: under its name while an item is being dragged")
    }

    static var insertAtPlayhead: String {
        String(localized: "Insert at Playhead", table: table, comment: "Video Studio Media panel: VoiceOver action — adds the item at the playhead, as a tap does")
    }

    /// Why 4K is shut (FS-12.10 §5): "4K needs 4K clips — 3 of your 5 clips
    /// are 1080p." or "… are smaller than 4K."
    static func fourKReason(_ verdict: VideoResolutionGate.Verdict) -> String? {
        guard case let .blocked(short, total, shared) = verdict else { return nil }
        if short == 1 {
            return shared.map {
                String(localized: "4K needs 4K clips — 1 of your \(total) clips is \($0.displayName).", table: table, comment: "Video Studio Video Settings: why 4K is dimmed — one clip falls short, and its resolution")
            } ?? String(localized: "4K needs 4K clips — 1 of your \(total) clips is smaller than 4K.", table: table, comment: "Video Studio Video Settings: why 4K is dimmed — one clip falls short")
        }
        if let shared {
            return String(localized: "4K needs 4K clips — \(short) of your \(total) clips are \(shared.displayName).", table: table, comment: "Video Studio Video Settings: why 4K is dimmed — how many clips fall short, and the resolution they all are")
        }
        return String(localized: "4K needs 4K clips — \(short) of your \(total) clips are smaller than 4K.", table: table, comment: "Video Studio Video Settings: why 4K is dimmed — how many clips fall short, at mixed resolutions")
    }

    static var done: String {
        String(localized: "Done", table: table, comment: "Video Studio Video Settings: closes the panel; every change is already applied")
    }

    static var ratioHeader: String {
        String(localized: "RATIO", table: table, comment: "Video Studio Video Settings: section header over the six frame ratios")
    }

    static var fitOnBackground: String {
        String(localized: "Fit on Background", table: table, comment: "Video Studio Video Settings: the whole clip shows, on the background")
    }

    static var fillCrop: String {
        String(localized: "Fill (Crop)", table: table, comment: "Video Studio Video Settings: the clip fills the frame, cropped from the middle")
    }

    static var backgroundHeader: String {
        String(localized: "BACKGROUND", table: table, comment: "Video Studio Video Settings: section header over what shows around a fitted clip")
    }

    static var blur: String {
        String(localized: "Blur", table: table, comment: "Video Studio Video Settings: the background is the clip itself, blurred; also the slider's name")
    }

    static var colour: String {
        String(localized: "Color", table: table, comment: "Video Studio Video Settings: the background is one color")
    }

    static var image: String {
        String(localized: "Image", table: table, comment: "Video Studio Video Settings: the background is a library photo")
    }

    static var customColour: String {
        String(localized: "Custom Color", table: table, comment: "Video Studio Video Settings: picks a background color of one's own")
    }

    static var chooseImage: String {
        String(localized: "Choose…", table: table, comment: "Video Studio Video Settings: picks the library photo behind fitted clips")
    }

    static var imageUnavailable: String {
        String(localized: "Image unavailable — choose another.", table: table, comment: "Video Studio Video Settings: the background photo was deleted or can no longer be read")
    }

    static var resolutionHeader: String {
        String(localized: "RESOLUTION", table: table, comment: "Video Studio Video Settings: section header over 720p / 1080p / 4K")
    }

    static var frameRateHeader: String {
        String(localized: "FRAME RATE", table: table, comment: "Video Studio Video Settings: section header over 24 / 30 / 60")
    }

    static var codecHeader: String {
        String(localized: "CODEC", table: table, comment: "Video Studio Video Settings: section header over H.264 / HEVC")
    }

    static var hevcNote: String {
        String(localized: "HEVC is about 40% smaller; some older devices can’t play it.", table: table, comment: "Video Studio Video Settings: under the codec choice")
    }

    static var output: String {
        String(localized: "Output", table: table, comment: "Video Studio Video Settings: the row that states the frame size, length and estimated file size")
    }

    static var changesApplyRightAway: String {
        String(localized: "Changes apply right away — Export uses them.", table: table, comment: "Video Studio Video Settings: under the Output row")
    }

    /// "Ratio 9:16" for VoiceOver.
    static func ratioLabel(_ ratio: String) -> String {
        String(localized: "Ratio \(ratio)", table: table, comment: "Video Studio Video Settings: VoiceOver name of a ratio button")
    }

    /// "4K, unavailable" for VoiceOver (FS-12.10 §7).
    static func unavailable(_ name: String) -> String {
        String(localized: "\(name), unavailable", table: table, comment: "Video Studio Video Settings: VoiceOver name of a dimmed choice, e.g. 4K, unavailable")
    }

    /// "9:16 · Fill": the frame's ratio and framing, over the frame.
    static func frameLabel(_ recipe: VideoProjectRecipe) -> String {
        let framing = recipe.framing == .fill
            ? String(localized: "Fill", table: table, comment: "Video Studio: the frame label's framing word — clips fill the frame")
            : String(localized: "Fit", table: table, comment: "Video Studio: the frame label's framing word — clips fit on the background")
        return "\(recipe.aspect.displayName) · \(framing)"
    }

    static func backgroundKind(_ kind: VideoBackground.Kind) -> String {
        switch kind {
        case .blur: blur
        case .colour: colour
        case .image: image
        }
    }

    /// A swatch's VoiceOver name.
    static func colourSwatch(_ colour: OverlayColor) -> String {
        switch colour {
        case .black: String(localized: "Black", table: table, comment: "Video Studio Video Settings: the black background swatch")
        case .white: String(localized: "White", table: table, comment: "Video Studio Video Settings: the white background swatch")
        default: String(localized: "Grey", table: table, comment: "Video Studio Video Settings: the grey background swatch")
        }
    }

    /// "Video Settings, 16:9, 1080p, 30 fps" — the button's VoiceOver
    /// name on every layout (FS-12.10 §7).
    static func videoSettingsAccessibility(_ recipe: VideoProjectRecipe) -> String {
        "\(videoSettings), \(recipe.aspect.displayName), \(recipe.resolution.displayName), \(framesPerSecond(recipe.frameRate.rawValue))"
    }

    static var exportVideo: String {
        String(localized: "Export Video", table: table, comment: "Video Studio: title of the export panel")
    }

    static var close: String {
        String(localized: "Close", table: table, comment: "Video Studio: closes a panel")
    }

    static var custom: String {
        String(localized: "Custom", table: table, comment: "Video Studio Export: the row that exports at the project's own Video Settings; a tap opens them")
    }

    static var savedToPhotos: String {
        String(localized: "Saved to Photos as a new video", table: table, comment: "Video Studio Export: where the exported video goes")
    }

    static var chooseWhereItGoes: String {
        String(localized: "Choose where it goes next", table: table, comment: "Video Studio Export, server photos: the file goes to the export sheet after rendering")
    }

    static var export: String {
        String(localized: "Export", table: table, comment: "Video Studio Export: starts the export")
    }

    static var exportEllipsis: String {
        String(localized: "Export…", table: table, comment: "Video Studio Export, server photos: renders, then asks where the file goes")
    }

    static var cancelExport: String {
        String(localized: "Cancel Export", table: table, comment: "Video Studio Export: stops the export in progress")
    }

    static var savingToPhotos: String {
        String(localized: "Saving to Photos…", table: table, comment: "Video Studio Export: the file is written and is going into the library")
    }

    static var exportStoppedWhenLeft: String {
        String(localized: "Export stopped when you left ShotDex. Export again to finish.", table: table, comment: "Video Studio Export: the export was cancelled because the app went to the background")
    }

    /// FS-12.10b §5: the device is short of twice the estimate.
    static func notEnoughSpace(_ needed: String) -> String {
        String(localized: "Not enough space to export — about \(needed) needed. Free up space, then try again.", table: table, comment: "Video Studio Export: the device lacks room for the file and its copy in Photos; the size is about twice the estimate")
    }

    /// "Exporting… 62%".
    static func exportingPercent(_ percent: Int) -> String {
        String(localized: "Exporting… \(percent)%", table: table, comment: "Video Studio Export: progress while the video is rendered")
    }

    /// "Exporting, 62 percent" for VoiceOver (FS-12.10b §6).
    static func exportingAccessibility(_ percent: Int) -> String {
        String(localized: "Exporting, \(percent) percent", table: table, comment: "Video Studio Export: VoiceOver reading of the progress bar")
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
