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
}
