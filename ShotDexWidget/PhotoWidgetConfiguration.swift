import AppIntents
import WidgetKit

/// What the Home Screen's own "Edit Widget" menu offers.
///
/// A widget only gets that menu when it is built on an `AppIntentConfiguration`,
/// so all four photo widgets are. The parameters deliberately stop at what a
/// menu can ask well: which album, how often it moves on, and how much the
/// photo is dimmed. A single photo, a typeface, a colour and the position of
/// the text are chosen in ShotDex, where there is a preview to choose them
/// against — the menu has no photo picker and no canvas.
struct ConfigurePhotoWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a Photo Source"
    static let description = IntentDescription(
        "Pick the photo or album this widget draws over. Leave both empty to use what you set in ShotDex."
    )

    @Parameter(
        title: "Design",
        description: "Which of your saved designs this widget wears. Leave empty for your first one."
    )
    var design: WidgetDesignEntity?

    @Parameter(
        title: "Photo",
        description: "One of your recent photos. Takes precedence over Album."
    )
    var photo: WidgetPhotoEntity?

    @Parameter(
        title: "Album",
        description: "Leave empty to use the photo or album you chose in ShotDex."
    )
    var album: WidgetAlbumEntity?

    @Parameter(title: "Change Photo", default: .followsApp)
    var rotation: WidgetRotationAppEnum

    @Parameter(title: "Dim Photo", default: .followsApp)
    var dimming: WidgetDimmingAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$design
            \.$photo
            \.$album
            \.$rotation
            \.$dimming
        }
    }
}

/// One saved design, as the configuration menu lists it.
///
/// This is what makes two photo widgets on one Home Screen able to look
/// nothing alike: the answer is stored per placed widget by WidgetKit, while
/// the design it names lives in the shared file both processes read.
struct WidgetDesignEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Design")
    static let defaultQuery = WidgetDesignQuery()

    var id: String
    var name: String
    var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    init(design: PhotoWidgetDesign) {
        id = design.id
        name = design.name
        summary = PhotoWidgetComponent.components(settings: design.settings)
            .map(\.title)
            .joined(separator: " · ")
    }
}

/// Answers the menu from the settings file the app wrote. Runs inside the
/// widget extension, so it reads the file rather than asking the app.
struct WidgetDesignQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetDesignEntity] {
        let designs = PhotoWidgetSettingsFile.read().designs
        return identifiers.compactMap { id in
            designs.first { $0.id == id }.map(WidgetDesignEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetDesignEntity] {
        PhotoWidgetSettingsFile.read().designs.map(WidgetDesignEntity.init)
    }

    /// The first design, so a widget dropped on the Home Screen and never
    /// opened still names something rather than reading "Choose".
    func defaultResult() async -> WidgetDesignEntity? {
        PhotoWidgetSettingsFile.read().designs.first.map(WidgetDesignEntity.init)
    }
}

/// One album, as the configuration menu lists it.
struct WidgetAlbumEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album")
    static let defaultQuery = WidgetAlbumQuery()

    var id: String
    var title: String
    var count: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(count.formatted()) photos"
        )
    }

    init(album: WidgetAlbumCatalog.Album) {
        id = album.id
        title = album.title
        count = album.count
    }
}

/// Answers the menu from the catalogue the app wrote.
///
/// This runs inside the widget extension, which is why it reads a file instead
/// of PhotoKit. An empty catalogue means the app has not been opened since the
/// widget was installed; the menu then shows nothing to choose, and the widget
/// says what to do about it.
struct WidgetAlbumQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAlbumEntity] {
        let catalog = WidgetAlbumCatalog.read()
        return identifiers.compactMap { catalog.album(id: $0).map(WidgetAlbumEntity.init) }
    }

    func suggestedEntities() async throws -> [WidgetAlbumEntity] {
        WidgetAlbumCatalog.read().albums.map(WidgetAlbumEntity.init)
    }

    func defaultResult() async -> WidgetAlbumEntity? { nil }
}

extension WidgetAlbumQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [WidgetAlbumEntity] {
        WidgetAlbumCatalog.read().matching(string).map(WidgetAlbumEntity.init)
    }
}

/// One photo, as the configuration menu lists it — with its thumbnail, since
/// a date on its own is not how anyone recognises a picture.
struct WidgetPhotoEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Photo")
    static let defaultQuery = WidgetPhotoQuery()

    var id: String
    var label: String
    var thumbnail: Data?

    var displayRepresentation: DisplayRepresentation {
        if let thumbnail {
            DisplayRepresentation(
                title: "\(label)",
                image: .init(data: thumbnail)
            )
        } else {
            DisplayRepresentation(title: "\(label)")
        }
    }

    init(photo: WidgetPhotoCatalog.Photo, catalog: WidgetPhotoCatalog) {
        id = photo.id
        label = photo.label
        thumbnail = catalog.thumbnailData(for: photo)
    }
}

/// Answers the photo picker from the catalogue the app wrote — again a file,
/// because this runs in the widget extension.
struct WidgetPhotoQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetPhotoEntity] {
        let catalog = WidgetPhotoCatalog.read()
        return identifiers.compactMap { identifier in
            catalog.photo(id: identifier).map { WidgetPhotoEntity(photo: $0, catalog: catalog) }
        }
    }

    func suggestedEntities() async throws -> [WidgetPhotoEntity] {
        let catalog = WidgetPhotoCatalog.read()
        return catalog.photos.map { WidgetPhotoEntity(photo: $0, catalog: catalog) }
    }

    func defaultResult() async -> WidgetPhotoEntity? { nil }
}

extension WidgetPhotoQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [WidgetPhotoEntity] {
        let catalog = WidgetPhotoCatalog.read()
        return catalog.matching(string).map { WidgetPhotoEntity(photo: $0, catalog: catalog) }
    }
}

/// How often an album moves on, with one extra case the in-app settings cannot
/// have: leave it to what ShotDex is set to.
enum WidgetRotationAppEnum: String, AppEnum {
    case followsApp
    case hourly
    case daily
    case never

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Change Photo")
    static let caseDisplayRepresentations: [WidgetRotationAppEnum: DisplayRepresentation] = [
        .followsApp: "As Set in ShotDex",
        .hourly: "Every Hour",
        .daily: "Every Day",
        .never: "Never",
    ]

    /// The stored rotation this stands for, or nil to keep the app's.
    var rotation: PhotoWidgetSettings.Rotation? {
        switch self {
        case .followsApp: nil
        case .hourly: .hourly
        case .daily: .daily
        case .never: .never
        }
    }
}

/// Dimming as a menu can ask it: a few steps, not a slider.
enum WidgetDimmingAppEnum: String, AppEnum {
    case followsApp
    case none
    case light
    case medium
    case heavy

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dim Photo")
    static let caseDisplayRepresentations: [WidgetDimmingAppEnum: DisplayRepresentation] = [
        .followsApp: "As Set in ShotDex",
        .none: "None",
        .light: "Light",
        .medium: "Medium",
        .heavy: "Heavy",
    ]

    var dimming: Double? {
        switch self {
        case .followsApp: nil
        case .none: 0
        case .light: 0.15
        case .medium: 0.3
        case .heavy: 0.5
        }
    }
}
