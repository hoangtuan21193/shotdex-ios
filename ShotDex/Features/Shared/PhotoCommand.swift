import SwiftUI

/// The photo commands a selection or a long-press offers, named and drawn in
/// one place — the album menu and the server menu read the same rows, so a
/// rename in one is a rename in both (FS-17.06 §3, D9).
enum PhotoCommand: String, CaseIterable, Identifiable {
    case edit
    case share
    case copy
    case pasteEdits
    case combine
    case cull
    case collage
    case video
    case resize
    /// Writes the selection to a folder in Files or a saved server (FS-03.07b).
    case export
    case addToCollection
    case captionKeywords
    case exportEXIF
    case duplicate
    case importToLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: String(localized: "Edit", comment: "Photo command")
        case .share: String(localized: "Share", comment: "Photo command")
        case .copy: String(localized: "Copy", comment: "Photo command")
        case .pasteEdits: String(localized: "Paste Edits", comment: "Photo command")
        case .combine: String(localized: "Combine Photos", comment: "Photo command")
        case .cull: MarkCopy.cull
        case .collage: String(localized: "Create Collage", comment: "Photo command")
        case .video: String(localized: "Create Video", comment: "Photo command")
        case .resize: String(localized: "Resize", comment: "Photo command")
        case .export: ExportCopy.command
        case .addToCollection: String(localized: "Add to Collection", comment: "Photo command")
        case .captionKeywords: String(localized: "Caption & Keywords…", table: KeywordCopy.table, comment: "Photo command: edit Photos caption and keywords of the selection (iOS 27)")
        case .exportEXIF: String(localized: "Export EXIF (CSV)", comment: "Photo command")
        case .duplicate: String(localized: "Duplicate", comment: "Photo command")
        case .importToLibrary: String(localized: "Import to Library", comment: "Photo command: copy server photos into the library")
        }
    }

    var systemImage: String {
        switch self {
        case .edit: "slider.horizontal.3"
        case .share: "square.and.arrow.up"
        case .copy: "doc.on.doc"
        case .pasteEdits: "doc.on.clipboard"
        case .combine: "square.3.layers.3d"
        case .cull: "flag.2.crossed"
        case .collage: "rectangle.split.2x2"
        case .video: "film"
        case .resize: "arrow.down.right.and.arrow.up.left"
        case .export: "square.and.arrow.up.on.square"
        case .addToCollection: "rectangle.stack.badge.plus"
        case .captionKeywords: "tag"
        case .exportEXIF: "doc.badge.arrow.up"
        case .duplicate: "plus.square.on.square"
        case .importToLibrary: "arrow.down.circle"
        }
    }

    var label: Label<Text, Image> { Label(title, systemImage: systemImage) }

    /// The selection ⋯ of an album, in order (FS-01.09 §2).
    static let albumSelectionMenu: [PhotoCommand] = [
        .pasteEdits, .combine, .cull, .collage, .video, .resize, .export, .addToCollection, .captionKeywords, .exportEXIF, .duplicate,
    ]

    /// What works on a file: the album's rows minus the Photos-only ones,
    /// in the album's order, then the server's own Import (FS-17.06 §3).
    static let serverSelectionMenu: [PhotoCommand] = [
        .pasteEdits, .combine, .collage, .video, .resize, .exportEXIF, .importToLibrary,
    ]

    /// The long-press menu of a server photo, before the Files group.
    static let serverPhotoMenu: [PhotoCommand] = [.edit, .share, .copy, .importToLibrary]
}
