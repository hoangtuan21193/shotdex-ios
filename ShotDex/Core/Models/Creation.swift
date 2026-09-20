import Foundation
import GRDB

/// One thing ShotDex made: a collage or a video, with the recipe that produced
/// it kept beside the exported photo.
///
/// The exported asset in Photos is a flat picture — it can be viewed, shared
/// and deleted, and nothing about it says which four photos went in or where
/// the caption sat. The recipe is what makes "open it again and keep editing"
/// possible, and it is the app's own data, so it lives in the app's own table
/// rather than anywhere near `photo_metadata` (the indexer upserts whole rows
/// there and would blank it on the next run).
///
/// `recipeJSON` is deliberately a plain `String`, not a nested `Codable`: GRDB
/// hands a nested type the database *row* rather than the column's JSON, so a
/// nested recipe would look for `clips` and `cells` as columns, fail, and
/// decode to something empty. `SmartAlbum` learned that the hard way.
struct Creation: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case collage
        case video
    }

    var id: String
    var kind: Kind
    /// The exported asset in Photos. Nil once the user deletes that photo —
    /// the recipe outlives it, because the photos it was built from usually do.
    var assetId: String?
    /// Epoch seconds. Newest first in the list.
    var createdAt: Int
    var updatedAt: Int
    /// The encoded `CollageRecipe` or `VideoProjectRecipe`.
    var recipeJSON: String

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        assetId: String?,
        createdAt: Int,
        updatedAt: Int,
        recipeJSON: String
    ) {
        self.id = id
        self.kind = kind
        self.assetId = assetId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recipeJSON = recipeJSON
    }
}

extension Creation: FetchableRecord, PersistableRecord {
    static let databaseTableName = "creations"
}

// MARK: - Recipe coding

extension Creation {
    /// A creation for a collage that has just been exported.
    static func collage(
        recipe: CollageRecipe,
        assetId: String?,
        id: String = UUID().uuidString,
        createdAt: Int = Int(Date.now.timeIntervalSince1970),
        now: Int = Int(Date.now.timeIntervalSince1970)
    ) throws -> Creation {
        Creation(
            id: id,
            kind: .collage,
            assetId: assetId,
            createdAt: createdAt,
            updatedAt: now,
            recipeJSON: try encode(recipe)
        )
    }

    static func video(
        recipe: VideoProjectRecipe,
        assetId: String?,
        id: String = UUID().uuidString,
        createdAt: Int = Int(Date.now.timeIntervalSince1970),
        now: Int = Int(Date.now.timeIntervalSince1970)
    ) throws -> Creation {
        Creation(
            id: id,
            kind: .video,
            assetId: assetId,
            createdAt: createdAt,
            updatedAt: now,
            recipeJSON: try encode(recipe)
        )
    }

    /// The collage recipe, or nil when this row is a video or its JSON no
    /// longer decodes — a recipe written by a build that has since changed
    /// shape is a creation that can still be *seen*, just not reopened.
    var collageRecipe: CollageRecipe? {
        guard kind == .collage else { return nil }
        return try? Self.decode(CollageRecipe.self, from: recipeJSON)
    }

    var videoRecipe: VideoProjectRecipe? {
        guard kind == .video else { return nil }
        return try? Self.decode(VideoProjectRecipe.self, from: recipeJSON)
    }

    /// Every asset the recipe draws from, in order, without decoding twice.
    /// Used to fetch the `PHAsset`s an editor needs before it reopens.
    var sourceAssetIds: [String] {
        switch kind {
        case .collage: collageRecipe?.cells.compactMap(\.assetID) ?? []
        case .video: videoRecipe?.clips.map(\.assetID) ?? []
        }
    }

    private static func encode(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
