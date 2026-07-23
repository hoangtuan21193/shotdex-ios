import Foundation
import GRDB

/// A user-created smart album: a named, saved rule query. Unlike the Apple
/// system smart albums (Favorites, Screenshots…) surfaced by PhotoKit, this is
/// an app-level saved filter — PhotoKit cannot create custom-predicate smart
/// albums. Its photos are resolved by replaying `query` through
/// `LibraryQueryDAO`.
struct SmartAlbum: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// The album's conditions (match mode + rules).
    var query: SmartAlbumQuery
    /// Creation time, epoch seconds. Newest sorts first in the grid.
    var createdAt: Int

    init(id: String, name: String, query: SmartAlbumQuery, createdAt: Int) {
        self.id = id
        self.name = name
        self.query = query
        self.createdAt = createdAt
    }

    // MARK: Persistence
    //
    // `query` is stored as a JSON *string* in the existing `criteria` text
    // column (see `AppDatabase` migration). We encode/decode that JSON
    // explicitly here rather than leaning on GRDB's implicit nested-Codable
    // handling: on decode GRDB presents the database row (not the column's
    // JSON) to a nested `Codable`, so `SmartAlbumQuery.init(from:)` would look
    // for `rules`/`matchMode` as columns, fail, and silently yield an empty
    // query — the album then matched the whole library. Treating `criteria` as
    // a plain `String` column sidesteps that entirely.

    private enum CodingKeys: String, CodingKey {
        case id, name, criteria, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        let json = try container.decode(String.self, forKey: .criteria)
        // `SmartAlbumQuery`'s own decoder is tolerant and migrates the legacy
        // `FilterCriteria` JSON shape, so pre-rule-builder albums keep working.
        query = (try? JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        let data = try JSONEncoder().encode(query)
        try container.encode(String(decoding: data, as: UTF8.self), forKey: .criteria)
    }
}

extension SmartAlbum: FetchableRecord, PersistableRecord {
    static let databaseTableName = "smart_albums"
}
