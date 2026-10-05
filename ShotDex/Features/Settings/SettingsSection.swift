import Foundation

/// One item in the Settings sidebar, at regular width (`DESIGN.md` §10.1f).
///
/// Nine items, in reading order — the order of the four headings
/// (`SettingsCategory`) the compact root groups them under, so the sidebar and
/// the phone's root list read the same top to bottom (FS-08.01b §1). Each one
/// owns one or more `SettingsGroup`s — the `Section`s the screen has always
/// drawn — so the sidebar is a grouping of the existing content, never a
/// second copy of it.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photoLibrary
    case display
    case playback
    case subjectScan
    case cameraDatabase
    case sharingAndExport
    case widgets
    case notifications
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
        case .display: "Display"
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

    /// The colour of the item's icon tile (FS-08.01b §2). A system colour, never
    /// the amber accent — accent is for state ShotDex draws (DESIGN §10.6).
    var tint: SettingsTint {
        switch self {
        case .photoLibrary: .blue
        case .display: .indigo
        case .playback: .pink
        case .subjectScan: .teal
        case .cameraDatabase: .brown
        case .sharingAndExport: .green
        case .widgets: .mint
        case .notifications: .red
        case .support: .gray
        }
    }

    /// The heading the item sits under, in both layouts.
    var category: SettingsCategory {
        switch self {
        case .photoLibrary, .display, .playback, .subjectScan, .cameraDatabase: .libraryAndViewing
        case .sharingAndExport: .sharingAndExport
        case .widgets, .notifications: .widgetsAndNotifications
        case .support: .help
        }
    }

    /// The rows the compact root shows for this item — one each, except
    /// Sharing and Export, which the phone splits into its three settings so
    /// each row can say its own value (FS-08.01b §1).
    var destinations: [SettingsDestination] {
        SettingsDestination.allCases.filter { $0.section == self }
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
        case .display: [.display, .statistics]
        case .playback: [.playback]
        case .subjectScan: [.subjectScan]
        case .sharingAndExport: [.sharing, .export, .fileServers]
        case .cameraDatabase: [.cameraDatabase]
        case .support: [.support]
        }
    }

    /// Whether the item's pane is a list of rows a search result can scroll
    /// to. Support's pane is the support screen itself, which has none of the
    /// rows the index names.
    var drawsRows: Bool { self != .support }
}

/// The four headings of Settings, in sentence case (FS-08.01b §1).
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case libraryAndViewing
    case sharingAndExport
    case widgetsAndNotifications
    case help

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .libraryAndViewing: LocalizedStringResource("Library and viewing", comment: "Settings heading over Photo Library, Display, Playback, People and Pets, Camera Database")
        case .sharingAndExport: LocalizedStringResource("Sharing and export", comment: "Settings heading over Metadata When Sharing, Resize Presets, File Servers")
        case .widgetsAndNotifications: LocalizedStringResource("Widgets and notifications", comment: "Settings heading over Widgets and Notifications")
        case .help: LocalizedStringResource("Help", comment: "Settings heading over Support")
        }
    }

    /// The sidebar items under this heading, in sidebar order.
    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.category == self }
    }

    /// The compact root's rows under this heading.
    var destinations: [SettingsDestination] {
        sections.flatMap(\.destinations)
    }
}

/// One row of the compact root — what a tap there pushes.
///
/// Eleven rows from nine items: the phone's root says each setting's value on
/// its row, and "Sharing and Export" has three settings with three different
/// values. Derived from `SettingsSection` (every case names its section), so
/// the two layouts stay one list in two arrangements.
enum SettingsDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photoLibrary
    case display
    case playback
    case subjectScan
    case cameraDatabase
    case metadataWhenSharing
    case resizePresets
    case fileServers
    case widgets
    case notifications
    case support

    var id: String { rawValue }

    var section: SettingsSection {
        switch self {
        case .photoLibrary: .photoLibrary
        case .display: .display
        case .playback: .playback
        case .subjectScan: .subjectScan
        case .cameraDatabase: .cameraDatabase
        case .metadataWhenSharing, .resizePresets, .fileServers: .sharingAndExport
        case .widgets: .widgets
        case .notifications: .notifications
        case .support: .support
        }
    }

    /// The row's title — the section's own, or the row label's for the three
    /// that split Sharing and Export, so the root and the row it opens agree.
    var title: LocalizedStringResource {
        switch self {
        case .metadataWhenSharing: SettingsRowLabel.metadataWhenSharing.text
        case .resizePresets: SettingsRowLabel.resizePresets.text
        case .fileServers: SettingsRowLabel.fileServers.text
        default: section.title
        }
    }

    var systemImage: String {
        switch self {
        case .metadataWhenSharing: "square.and.arrow.up"
        // DESIGN.md §8: Compress / Resize and Upload to Server.
        case .resizePresets: "arrow.down.right.and.arrow.up.left"
        case .fileServers: "server.rack"
        default: section.systemImage
        }
    }

    var tint: SettingsTint {
        switch self {
        case .metadataWhenSharing: .green
        case .resizePresets: .purple
        case .fileServers: .cyan
        default: section.tint
        }
    }

    /// The groups the pushed page draws.
    var groups: [SettingsGroup] {
        switch self {
        case .metadataWhenSharing: [.sharing]
        case .resizePresets: [.export]
        case .fileServers: [.fileServers]
        default: section.groups
        }
    }

    /// `false` for the rows that push a screen of their own instead of a page
    /// of rows: Resize Presets and File Servers open their lists directly — a
    /// page whose only content is one link to them would be a tap for nothing —
    /// and Support is the support screen.
    var drawsRows: Bool {
        switch self {
        case .resizePresets, .fileServers, .support: false
        default: true
        }
    }

    /// The root row that leads to a given settings row.
    static func containing(_ label: SettingsRowLabel) -> SettingsDestination {
        allCases.first { $0.groups.contains(label.group) } ?? .photoLibrary
    }
}

/// One `Section` of the Settings list — the fourteen the screen draws.
///
/// The sidebar groups Library Size and Privacy under Photo Library, and the
/// phone's root splits Sharing and Export in three; both are mappings onto this
/// one list, never a hand-written per-device copy of it (`NF-05` §37: a list
/// written out by hand is how a whole row went missing).
enum SettingsGroup: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photoLibrary
    case notifications
    case widgets
    case display
    /// Show Insights (FS-07.02 §6) — drawn under Thumbnail Metadata, in the
    /// sidebar's Display item.
    case statistics
    case playback
    case subjectScan
    case libraryStorage
    case sharing
    case export
    case fileServers
    case cameraDatabase
    case support
    case privacy

    var id: String { rawValue }
}
