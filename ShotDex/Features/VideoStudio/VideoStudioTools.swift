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

    /// Where each tool lives on a window of `windowClass` (FS-12.04 §3). Every
    /// layout offers all five; what changes is the shape: a bottom row on the
    /// phone and the Duo's inner display, the rail on the cover, pool tabs
    /// and Look as the default inspector on an iPad.
    enum Placement: Equatable {
        case bottomRow, coverRail, poolTab, dockButton, defaultPanel
    }

    static func placement(of tool: VideoAddTool, in windowClass: VideoStudioWindowClass) -> Placement {
        switch windowClass {
        case .phone, .duoInner: .bottomRow
        case .duoCover: .coverRail
        case .iPadLandscape: tool == .look ? .defaultPanel : .poolTab
        case .iPadPortrait: tool == .look ? .defaultPanel : .dockButton
        }
    }

    /// The tools a window of `windowClass` offers — always all five.
    static func addTools(for windowClass: VideoStudioWindowClass) -> [VideoAddTool] {
        allCases.filter { tool in
            switch placement(of: tool, in: windowClass) {
            case .bottomRow, .coverRail, .poolTab, .dockButton, .defaultPanel: true
            }
        }
    }

    /// What the five tools do while an item is selected (FS-12.04 §5).
    enum SelectionBehaviour: Equatable {
        /// The phone: the row is replaced outright by ✕ · name · ✓.
        case replacedBySessionFooter
        /// The Duo, inner and cover: drawn at white 30 %, take no touches.
        case inert
        /// iPad landscape: the pool stays usable; inserting from it is ✓ for
        /// the selected item first.
        case usableCommittingFirst
        /// iPad portrait: the dock's four add buttons make way for the item's
        /// command row.
        case yieldsToCommands
    }

    static func selectionBehaviour(in windowClass: VideoStudioWindowClass) -> SelectionBehaviour {
        switch windowClass {
        case .phone: .replacedBySessionFooter
        case .duoInner, .duoCover: .inert
        case .iPadLandscape: .usableCommittingFirst
        case .iPadPortrait: .yieldsToCommands
        }
    }

    /// Whether the tools refuse touches right now.
    static func toolsAreInert(in windowClass: VideoStudioWindowClass, isSelecting: Bool) -> Bool {
        isSelecting && selectionBehaviour(in: windowClass) == .inert
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
    /// Video sound, Add Music from Files…, My Music (FS-12.04 §3).
    case music
    /// The photo library inside the panel (FS-12.09).
    case media
    /// Export Video (FS-12.10b): opening it never starts an export.
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .look: VideoStudioCopy.look
        case .videoSettings: VideoStudioCopy.videoSettings
        case .music: VideoStudioCopy.addMusic
        case .media: VideoStudioCopy.media
        case .export: VideoStudioCopy.exportVideo
        }
    }

    var systemImage: String {
        switch self {
        case .look: "camera.filters"
        case .videoSettings: "aspectratio"
        case .music: "music.note"
        case .media: VideoAddTool.media.systemImage
        case .export: "square.and.arrow.down"
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

// MARK: - Item commands (FS-12.04b)

/// What is selected, as far as its command row is concerned.
enum VideoItemKind: CaseIterable, Equatable {
    case videoClip, photoClip, freezeClip, text, sticker, music
}

/// One cell of a selected item's command row (FS-12.04b §3–4).
enum VideoItemCommand: String, CaseIterable, Identifiable {
    case split, trim, speed, volume, replace, freeze, duplicate, look, rotate
    /// A multi-select group's (FS-12.11 §5): Motion for every clip in it,
    /// and Move without dragging.
    case motion, move
    case edit, font, color, style, align, animate
    case beats, ducking, addTrack
    case delete

    var id: String { rawValue }

    /// A *section* command lights its cell and brings its block or row to
    /// the top of the panel; tapping it again turns it off. An *action*
    /// command does its thing once and never lights.
    var isSection: Bool {
        switch self {
        case .trim, .speed, .volume, .look, .motion, .edit, .font, .color, .style, .align, .animate, .beats, .ducking: true
        case .split, .replace, .freeze, .duplicate, .rotate, .move, .addTrack, .delete: false
        }
    }

    var isDestructive: Bool { self == .delete }

    var title: LocalizedStringKey {
        switch self {
        case .split: "Split"
        case .trim: LocalizedStringKey(VideoStudioCopy.trim)
        case .speed: "Speed"
        case .volume: "Volume"
        case .replace: "Replace"
        case .freeze: "Freeze"
        case .duplicate: LocalizedStringKey(VideoStudioCopy.duplicate)
        case .look: LocalizedStringKey(VideoStudioCopy.look)
        case .rotate: "Rotate"
        case .motion: LocalizedStringKey(VideoStudioCopy.motion)
        case .move: LocalizedStringKey(VideoStudioCopy.move)
        case .edit: "Edit"
        case .font: "Font"
        case .color: "Color"
        case .style: "Style"
        case .align: "Align"
        case .animate: "Animate"
        case .beats: LocalizedStringKey(VideoStudioCopy.beats)
        case .ducking: LocalizedStringKey(VideoStudioCopy.ducking)
        case .addTrack: "Add Track"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .split: "scissors"
        case .trim: "arrow.left.and.line.vertical.and.arrow.right"
        case .speed: "speedometer"
        case .volume: "speaker.wave.2"
        case .replace: "arrow.triangle.2.circlepath"
        case .freeze: "snowflake"
        case .duplicate: "plus.square.on.square"
        case .look: "camera.filters"
        case .rotate: "rotate.right"
        case .motion: "wand.and.rays"
        case .move: "arrow.left.arrow.right"
        case .edit: "character.cursor.ibeam"
        case .font: "textformat.alt"
        case .color: "paintpalette"
        case .style: "a.square"
        case .align: "text.aligncenter"
        case .animate: "wand.and.stars"
        case .beats: "metronome"
        case .ducking: "waveform.badge.minus"
        case .addTrack: "plus"
        case .delete: "trash"
        }
    }

    /// Commands whose feature is not built yet: hidden, not dimmed, and the
    /// rest keep their order (FS-12.04b §3). Beats is FS-12.12, Ducking
    /// FS-12.13, a clip's own Look is FS-12.06c — each plan takes its
    /// command out of this list when it lands.
    static let notYetBuilt: Set<VideoItemCommand> = [.beats, .ducking]

    /// The row for `kind`, in the spec's order — most used first, Delete
    /// last — on every layout. `singleVideo` adds Rotate before Delete on a
    /// video clip (Photo Detail → Edit).
    static func commands(for kind: VideoItemKind, singleVideo: Bool = false) -> [VideoItemCommand] {
        let row: [VideoItemCommand] = switch kind {
        case .videoClip: [.split, .trim, .speed, .volume, .replace, .freeze, .duplicate, .look]
            + (singleVideo ? [.rotate] : []) + [.delete]
        case .photoClip: [.split, .trim, .replace, .duplicate, .look, .delete]
        case .freezeClip: [.split, .trim, .duplicate, .look, .delete]
        case .text: [.edit, .font, .color, .style, .align, .animate, .duplicate, .delete]
        case .sticker: [.animate, .duplicate, .delete]
        case .music: [.beats, .ducking, .replace, .addTrack, .duplicate, .delete]
        }
        return row.filter { !notYetBuilt.contains($0) }
    }
}

extension VideoItemCommand {
    /// A multi-select group's row (FS-12.11 §5): Speed · Volume · Look ·
    /// Motion · Move · Duplicate · Delete. A group with no video has no
    /// Speed and no Volume — hidden, not dimmed (FS-12.04b §3).
    static func groupCommands(hasVideo: Bool) -> [VideoItemCommand] {
        (hasVideo ? [.speed, .volume] : []) + [.look, .motion, .move, .duplicate, .delete]
    }

    /// How a window lays the row out: one scrolling row everywhere — the
    /// Duo's 264pt column included — never folded into a grid
    /// (FS-12.04b §1).
    enum RowShape: Equatable { case scrollingRow }

    static func rowShape(in _: VideoStudioWindowClass) -> RowShape { .scrollingRow }

    /// The row a window of `windowClass` shows for `kind`: the same list on
    /// every layout — the iPad has no command the phone lacks.
    static func commands(
        for kind: VideoItemKind,
        in _: VideoStudioWindowClass,
        singleVideo: Bool = false
    ) -> [VideoItemCommand] {
        commands(for: kind, singleVideo: singleVideo)
    }
}

extension VideoItemKind {
    init(_ clip: VideoClip) {
        switch clip.kind {
        case .video: self = .videoClip
        case .photo: self = .photoClip
        case .freeze: self = .freezeClip
        }
    }
}
