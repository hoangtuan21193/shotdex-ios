import Foundation

/// The small digest the app writes for its widgets to read.
///
/// Duplicated verbatim in the app target (`App/GearSnapshot.swift`). The two
/// targets cannot share a source file: each is a file-system-synchronised
/// folder, so a file belongs to exactly one of them, and a twenty-line value
/// type is cheaper to keep in step than a third framework target would be.
struct GearSnapshot: Codable, Equatable {
    var totalPhotos: Int
    var photosThisMonth: Int
    var topCamera: String?
    var topLens: String?
    var generatedAt: Date

    static let empty = GearSnapshot(
        totalPhotos: 0,
        photosThisMonth: 0,
        topCamera: nil,
        topLens: nil,
        generatedAt: .distantPast
    )

    /// Shared container the app writes to and the widget reads from. Both
    /// targets must carry this App Group, and both degrade to a placeholder
    /// when they cannot reach it.
    static let appGroupIdentifier = "group.com.hoangtuan.shotdex"
    static let fileName = "gear-snapshot.json"
    static let coverFileName = "gear-cover.jpg"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    static func read() -> GearSnapshot? {
        guard let url = containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(GearSnapshot.self, from: data)
    }

    static func readCoverData() -> Data? {
        guard let url = containerURL?.appendingPathComponent(coverFileName) else { return nil }
        return try? Data(contentsOf: url)
    }
}
