import SwiftUI

/// The five tools of the Video Studio's bottom row (FS-12.04 §2–3): each one
/// **adds** to the timeline, or — Look — opens the one place the whole
/// video's look is changed. Nothing else is a tool any more: Ratio and
/// Background are Video Settings, Volume is the Music panel's Video sound.
///
/// One list, in one order, read by every layout — the phone's row, the
/// tablet's rail and pool, the Duo's cover rail (NF-05 §1).
enum VideoAddTool: String, CaseIterable, Identifiable {
    case media, text, sticker, music, look

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .media: LocalizedStringKey(VideoStudioCopy.media)
        case .text: "Text"
        case .sticker: "Sticker"
        case .music: "Music"
        case .look: LocalizedStringKey(VideoStudioCopy.look)
        }
    }

    var systemImage: String {
        switch self {
        case .media: "play.rectangle.on.rectangle"
        case .text: "textformat"
        case .sticker: "face.smiling"
        case .music: "music.note"
        case .look: "camera.filters"
        }
    }

    /// The row of a window with no media pool: all five, in order.
    static var bottomRow: [VideoAddTool] { allCases }

    /// The row of a window whose media pool carries the inserts — Media,
    /// Sticker and Music are pool tabs there; Text has no template library to
    /// drag from, so it stays a button, and Look is the inspector's default.
    static var poolRow: [VideoAddTool] { [.text, .look] }
}

/// The panels a tool opens when nothing is selected (FS-12.04 §4).
enum VideoToolPanel: String, Equatable, Identifiable, CaseIterable {
    /// Filter · Adjust · Color for the whole video. A shell around the
    /// existing controls until the Look plan replaces its insides.
    case look
    /// Ratio and Background for now; the Video Settings plan fills it.
    case videoSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .look: VideoStudioCopy.look
        case .videoSettings: VideoStudioCopy.videoSettings
        }
    }

    var systemImage: String {
        switch self {
        case .look: "camera.filters"
        case .videoSettings: "aspectratio"
        }
    }
}

/// The three tabs of the Look panel shell.
enum VideoLookTab: String, CaseIterable, Identifiable {
    case filter, adjust, color

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .filter: "Filter"
        case .adjust: "Adjust"
        case .color: "Color"
        }
    }
}

extension VideoStudioMetrics {
    /// The fill of a tool cell whose panel is open, and of a lit item
    /// command: white 14 %, not accent — accent is Export's alone.
    static let openCellFill = Color.white.opacity(0.14)
}
