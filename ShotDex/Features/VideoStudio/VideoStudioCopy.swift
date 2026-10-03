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
}
