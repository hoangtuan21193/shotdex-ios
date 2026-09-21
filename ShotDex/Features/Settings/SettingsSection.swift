import Foundation

/// One item in the Settings sidebar, at regular width (`DESIGN.md` §10.1f).
///
/// Nine items, in reading order. Each one owns one or more `SettingsGroup`s —
/// the `Section`s the screen has always drawn — so the sidebar is a grouping of
/// the existing content, never a second copy of it.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photoLibrary
    case notifications
    case widgets
    case display
    case playback
    case subjectScan
    case sharingAndExport
    case cameraDatabase
    case support

    var id: String { rawValue }

    /// The sidebar label. Where an item carries exactly one group, this is the
    /// wording of that group's own header — one thing must not answer to two
    /// names between the sidebar and the list.
    var title: LocalizedStringResource {
        switch self {
        case .photoLibrary: "Photo Library"
        case .notifications: "Notifications"
        case .widgets: "Widgets"
        case .display: "Thumbnail Metadata"
        case .playback: "Playback"
        case .subjectScan: "People and Pets"
        case .sharingAndExport: "Sharing and Export"
        case .cameraDatabase: "Camera Database"
        case .support: "Support"
        }
    }

    /// Every symbol here exists from iOS 15, so the sidebar needs no
    /// `#available` branch.
    var systemImage: String {
        switch self {
        case .photoLibrary: "photo.stack"
        case .notifications: "bell"
        case .widgets: "square.grid.2x2"
        case .display: "text.below.photo"
        case .playback: "play.rectangle"
        // Not a magnifying glass: the search field sits four rows above, and two
        // magnifiers in one sidebar read as two searches.
        case .subjectScan: "person.2"
        case .sharingAndExport: "square.and.arrow.up"
        case .cameraDatabase: "camera"
        case .support: "questionmark.circle"
        }
    }

    /// The groups this item shows, in the order the detail pane draws them.
    ///
    /// Library Size and Privacy have no item of their own: the first is two
    /// rows of numbers read once, the second is an explanation plus one
    /// destructive button, and §10.1 puts a destructive action at the end of
    /// the list it belongs to. Both belong to the photo library.
    var groups: [SettingsGroup] {
        switch self {
        case .photoLibrary: [.photoLibrary, .libraryStorage, .privacy]
        case .notifications: [.notifications]
        case .widgets: [.widgets]
        case .display: [.display]
        case .playback: [.playback]
        case .subjectScan: [.subjectScan]
        case .sharingAndExport: [.sharing, .export]
        case .cameraDatabase: [.cameraDatabase]
        case .support: [.support]
        }
    }
}

/// One `Section` of the Settings list — the twelve the screen has always drawn,
/// **in the order the compact layout draws them**.
///
/// This is why there are two enums rather than one. The sidebar groups Library
/// Size and Privacy under Photo Library; driving the compact list from the
/// nine-item order would therefore lift both of them to the top of the phone's
/// screen, which is a layout change nobody asked for. Two orders, one mapping,
/// and no hand-written per-device list — which is the rule that matters
/// (`NF-05` §37: a list written out by hand is how a whole row went missing).
enum SettingsGroup: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photoLibrary
    case notifications
    case widgets
    case display
    case playback
    case subjectScan
    case libraryStorage
    case sharing
    case export
    case cameraDatabase
    case support
    case privacy

    var id: String { rawValue }
}
