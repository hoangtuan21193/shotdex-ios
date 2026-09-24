import Foundation

/// Every row in Settings that a reader could go looking for, named once.
///
/// The row draws its title from here and the search index is derived from
/// `allCases`, so there is no second list of labels to fall out of step with
/// the screen. That is the whole reason this type exists: the obvious way to
/// build a settings search — write the labels out again in an index — is a
/// copy that goes stale the first time a word changes.
///
/// `LocalizedStringResource` rather than `String`: a `String` passed to
/// `Toggle(_:isOn:)` binds the `StringProtocol` overload and quietly stops
/// being localized. Rather than `LocalizedStringKey`: that one cannot be read
/// back, and the index has to read the text to normalize it for matching.
/// Declared outside a view, these are still extracted into the String Catalog,
/// and the keys are unchanged from the literals they replaced.
///
/// **Not** listed here: section headers and footers (search answers with rows,
/// not with groups), the Cancel buttons inside the two progress rows, and the
/// progress readouts themselves. None of them is a destination.
enum SettingsRowLabel: String, CaseIterable, Identifiable, Hashable, Sendable {

    // Photo Library
    case access
    case manageSelectedPhotos
    case openPhotoSettings
    case indexedPhotosAndVideos
    case lastIndexed
    case continueIndexing
    case reindexLibrary
    case useCellularData
    case keepScreenAwake
    case lookUpPlaceNames

    // Notifications
    case dailyOnThisDayReminder
    case remindMeAt
    case notificationsDenied
    case openNotificationSettings

    // Widgets
    case photoWidget

    // Thumbnail Metadata
    case fileTypeBadge
    case iso
    case aperture
    case shutterSpeed
    case focalLength
    case focalLengthStyle
    case megapixels
    case fileSize

    // Playback
    case autoplayVideos
    case viewFullHDR

    // People and Pets
    case scanned
    case findPeopleAndPets
    case scanAgain
    case clearScanResults

    // Library Size
    case photosAndVideos
    case measured

    // Sharing
    case includeLocation

    // Export
    case resizePresets

    // File Servers
    case fileServers

    // Camera Database
    case unknownCameras
    case resetCustomMappings

    // Support
    case support

    // Privacy
    case clearLocalMetadataIndex

    var id: String { rawValue }

    /// The words on screen. Changing one of these changes the row and the
    /// search index together, which is the point.
    var text: LocalizedStringResource {
        switch self {
        case .access: "Access"
        case .manageSelectedPhotos: "Manage Selected Photos"
        case .openPhotoSettings, .openNotificationSettings: "Open Settings"
        case .indexedPhotosAndVideos: "Indexed Photos and Videos"
        case .lastIndexed: "Last Indexed"
        // The row itself draws "Continue Indexing (12,495)" from the format
        // string `Continue Indexing (%@)` — one phrase for a translator rather
        // than a word with brackets bolted on in English word order. Search
        // indexes the name without the count, which is what anyone types.
        case .continueIndexing: "Continue Indexing"
        case .reindexLibrary: "Re-index Library"
        case .useCellularData: "Use Cellular Data for Indexing"
        case .keepScreenAwake: "Keep Screen Awake While Indexing"
        case .lookUpPlaceNames: "Look Up Place Names"
        case .dailyOnThisDayReminder: "Daily On This Day Reminder"
        case .remindMeAt: "Remind Me At"
        case .notificationsDenied: "Notifications"
        case .photoWidget: "Photo Widget"
        case .fileTypeBadge: "File Type"
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutterSpeed: "Shutter Speed"
        case .focalLength: "Focal Length"
        case .focalLengthStyle: "Focal Length Style"
        case .megapixels: "Megapixels"
        case .fileSize: "File Size"
        case .autoplayVideos: "Autoplay Videos"
        case .viewFullHDR: "View Full HDR"
        case .scanned: "Scanned"
        case .findPeopleAndPets: "Find People and Pets"
        case .scanAgain: "Scan Again"
        case .clearScanResults: "Clear Results"
        case .photosAndVideos: "Photos and Videos"
        case .measured: "Measured"
        case .includeLocation: "Include Location"
        case .resizePresets: "Resize Presets"
        case .fileServers: "File Servers"
        case .unknownCameras: "Unknown Cameras"
        case .resetCustomMappings: "Reset Custom Mappings"
        case .support: "Support"
        case .clearLocalMetadataIndex: "Clear Local Metadata Index"
        }
    }

    /// The same words, resolved — what a row hands to `Toggle`, `Button` and
    /// friends. Already localized, so the `StringProtocol` initializer those
    /// take is the right one and loses nothing: extraction happens on `text`.
    var title: String { String(localized: text) }

    /// Which `Section` draws the row.
    var group: SettingsGroup {
        switch self {
        case .access, .manageSelectedPhotos, .openPhotoSettings, .indexedPhotosAndVideos,
             .lastIndexed, .continueIndexing, .reindexLibrary,
             .useCellularData, .keepScreenAwake, .lookUpPlaceNames:
            .photoLibrary
        case .dailyOnThisDayReminder, .remindMeAt, .notificationsDenied, .openNotificationSettings:
            .notifications
        case .photoWidget:
            .widgets
        case .fileTypeBadge, .iso, .aperture, .shutterSpeed, .focalLength,
             .focalLengthStyle, .megapixels, .fileSize:
            .display
        case .autoplayVideos, .viewFullHDR:
            .playback
        case .scanned, .findPeopleAndPets, .scanAgain, .clearScanResults:
            .subjectScan
        case .photosAndVideos, .measured:
            .libraryStorage
        case .includeLocation:
            .sharing
        case .resizePresets:
            .export
        case .fileServers:
            .fileServers
        case .unknownCameras, .resetCustomMappings:
            .cameraDatabase
        case .support:
            .support
        case .clearLocalMetadataIndex:
            .privacy
        }
    }

    /// Words someone types for this row that are not in its title — the
    /// protocol names and the box people call it. Not localized: nobody
    /// translates "SMB".
    var searchAliases: [String] {
        switch self {
        case .fileServers: ["SMB", "SFTP", "NAS", "upload"]
        default: []
        }
    }

    /// When the row is on screen at all.
    ///
    /// The index is static and declares every row that can ever appear — it
    /// never reads live state, which is what keeps it pure and testable without
    /// standing up `AppDependencies`. The cost is that search can offer a row
    /// that is not there right now, so a result whose availability is not
    /// `.always` says so before the reader taps it.
    var availability: Availability {
        switch self {
        case .manageSelectedPhotos: .whenPhotoAccessLimited
        case .openPhotoSettings: .whenPhotoAccessDenied
        case .notificationsDenied, .openNotificationSettings: .whenNotificationsDenied
        case .continueIndexing: .whenIndexingUnfinished
        case .lastIndexed: .afterFirstIndex
        case .measured: .whileLibrarySizeIsPartial
        case .findPeopleAndPets: .whenScanIncomplete
        case .scanAgain: .whenScanComplete
        case .clearScanResults: .whenScanned
        default: .always
        }
    }

    enum Availability: Hashable, Sendable {
        case always
        case whenPhotoAccessLimited
        case whenPhotoAccessDenied
        case whenNotificationsDenied
        case whenIndexingUnfinished
        case afterFirstIndex
        case whileLibrarySizeIsPartial
        case whenScanIncomplete
        case whenScanComplete
        case whenScanned

        /// What a search result says under a row that may not be there. `nil`
        /// for `.always`, and never `nil` for anything else — a row that can
        /// hide has to explain itself, or tapping the result is a silent no-op.
        var explanation: LocalizedStringResource? {
            switch self {
            case .always: nil
            case .whenPhotoAccessLimited: "Shown when photo access is limited"
            case .whenPhotoAccessDenied: "Shown when photo access is denied"
            case .whenNotificationsDenied: "Shown when notifications are denied"
            case .whenIndexingUnfinished: "Shown when photos are left to index"
            case .afterFirstIndex: "Shown after the first index finishes"
            case .whileLibrarySizeIsPartial: "Shown while the size is still being measured"
            case .whenScanIncomplete: "Shown until every photo has been scanned"
            case .whenScanComplete: "Shown after every photo has been scanned"
            case .whenScanned: "Shown when a scan has found something"
            }
        }
    }
}
