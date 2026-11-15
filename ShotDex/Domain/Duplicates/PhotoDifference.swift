import Foundation

/// The facts Compare can set side by side for one photo (FS-06.06 §14.7).
/// `nil` is "unknown or none"; the screen shows *None*.
struct PhotoFacts: Equatable, Sendable {
    var date: Date?
    var fileSize: Int?
    var width: Int?
    var height: Int?
    /// "HEIC", "JPEG", "RAW + JPEG"…
    var format: String?
    var camera: String?
    var lens: String?
    var aperture: Double?
    var shutterSeconds: Double?
    var iso: Int?
    var focalLength: Double?
    var hasLocation = false
    var latitude: Double?
    var longitude: Double?
    /// The place in words, when the index has one.
    var placeName: String?
    var albums: [String] = []
    var rating = 0
    var keywords: [String] = []
    var isEdited = false
    /// "WhatsApp", "Export of DSC01234"…
    var source: String?
}

/// Only what differs between two photos, in a fixed order, the way Immich's
/// duplicate compare does it (FS-06.06 §14.7): two values differ when they
/// read differently on screen, lists are sets, the first five rows show and
/// the rest wait behind *Show N more*.
enum PhotoDifference {
    enum Field: CaseIterable, Sendable {
        case date, fileSize, dimensions, format, camera, lens, settings, location, albums, rating, keywords, edited, source

        var title: String {
            switch self {
            case .date: String(localized: "Date", comment: "What differs: row label, capture date")
            case .fileSize: String(localized: "Size", comment: "What differs: row label, file size")
            case .dimensions: String(localized: "Dimensions", comment: "What differs: row label, pixel width by height")
            case .format: String(localized: "Format", comment: "What differs: row label, file format like HEIC or JPEG")
            case .camera: String(localized: "Camera", comment: "What differs: row label")
            case .lens: String(localized: "Lens", comment: "What differs: row label")
            case .settings: String(localized: "Settings", comment: "What differs: row label, aperture, shutter, ISO and focal length")
            case .location: String(localized: "Location", comment: "What differs: row label")
            case .albums: String(localized: "Albums", comment: "What differs: row label")
            case .rating: String(localized: "Rating", comment: "What differs: row label, star rating")
            case .keywords: String(localized: "Keywords", comment: "What differs: row label")
            case .edited: String(localized: "Edited", comment: "What differs: row label and value, the photo was edited")
            case .source: String(localized: "Source", comment: "What differs: row label, where the copy came from")
            }
        }
    }

    struct Row: Equatable, Sendable, Identifiable {
        let field: Field
        let a: String
        let b: String
        var id: Field { field }
    }

    /// Rows shown before *Show N more*.
    static let visibleLimit = 5

    static func rows(_ a: PhotoFacts, _ b: PhotoFacts) -> [Row] {
        Field.allCases.compactMap { field in
            let left = display(field, a), right = display(field, b)
            // One basis: two values differ when they *read* differently —
            // the rounding Immich applies is the rounding the screen shows
            // (a date to the second, f/1.78 as f/1.8, bytes as MB). The date
            // compares on the second, so two zones of one instant agree.
            // Keywords are one keyword per case-folded spelling (FS-02.07).
            let differs = switch field {
            case .date: dateKey(a) != dateKey(b)
            case .keywords: Set(a.keywords.map(KeywordInput.caseKey)) != Set(b.keywords.map(KeywordInput.caseKey))
            default: left != right
            }
            return differs ? Row(field: field, a: left, b: right) : nil
        }
    }

    static func visible(_ rows: [Row], expanded: Bool) -> [Row] {
        expanded ? rows : Array(rows.prefix(visibleLimit))
    }

    static func hiddenCount(_ rows: [Row]) -> Int { max(0, rows.count - visibleLimit) }

    private static func dateKey(_ f: PhotoFacts) -> Int? {
        f.date.map { Int($0.timeIntervalSince1970.rounded(.down)) }
    }

    // MARK: Showing

    /// Albums once each, in name order; keywords once per case-folded
    /// spelling, the first spelling kept.
    private static func list(_ items: [String], key: (String) -> String) -> [String] {
        var seen: Set<String> = []
        return items.filter { seen.insert(key($0)).inserted }
            .sorted { key($0).localizedStandardCompare(key($1)) == .orderedAscending }
    }

    static func display(_ field: Field, _ f: PhotoFacts) -> String {
        let none = String(localized: "None", comment: "What differs: the photo has no value for this row")
        switch field {
        case .date:
            return f.date?.formatted(date: .abbreviated, time: .standard) ?? none
        case .fileSize:
            return f.fileSize.flatMap(MetadataFormatter.fileSize) ?? none
        case .dimensions:
            guard let width = f.width, let height = f.height, width > 0, height > 0 else { return none }
            // Pixel counts are never grouped ("4032", not "4,032").
            return String(localized: "\(String(width)) × \(String(height))", comment: "What differs: pixel dimensions, width by height, e.g. 4032 × 3024")
        case .format: return f.format.flatMap { $0.isEmpty ? nil : $0 } ?? none
        case .camera: return f.camera.flatMap { $0.isEmpty ? nil : $0 } ?? none
        case .lens: return f.lens.flatMap { $0.isEmpty ? nil : $0 } ?? none
        case .settings:
            // The grid's own formatter, so Compare reads like the grid.
            return MetadataFormatter.metadataLine([
                f.aperture.flatMap(MetadataFormatter.aperture),
                f.shutterSeconds.flatMap(MetadataFormatter.shutterSpeed),
                f.iso.flatMap(MetadataFormatter.iso),
                f.focalLength.flatMap(MetadataFormatter.focalLength),
            ]) ?? none
        case .location:
            guard f.hasLocation else { return none }
            return f.placeName.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "Yes", comment: "What differs: the photo has a location but no place name")
        case .albums:
            let albums = list(f.albums) { $0 }
            return albums.isEmpty ? none : albums.formatted(.list(type: .and, width: .narrow))
        case .rating:
            let stars = max(0, min(f.rating, 5))
            return stars == 0 ? none : String(localized: "\(stars) stars", comment: "What differs: star rating, e.g. 3 stars")
        case .keywords:
            let keywords = list(f.keywords, key: KeywordInput.caseKey)
            return keywords.isEmpty ? none : keywords.formatted(.list(type: .and, width: .narrow))
        case .edited:
            return f.isEdited
                ? String(localized: "Edited", comment: "What differs: row label and value, the photo was edited")
                : String(localized: "Original", comment: "What differs: value, the photo was not edited")
        case .source: return f.source.flatMap { $0.isEmpty ? nil : $0 } ?? none
        }
    }
}
