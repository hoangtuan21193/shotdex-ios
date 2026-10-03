import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-12.18 §5: a video draft is a `creations` row with no export date yet,
/// written and read through `CreationStore`, and read leniently.
@MainActor
struct VideoDraftStoreTests {
    private let clipA = "11111111-1111-1111-1111-111111111111"
    private let clipB = "22222222-2222-2222-2222-222222222222"
    private let clipC = "33333333-3333-3333-3333-333333333333"

    private func draftRow(_ json: String, id: String = "draft-1") -> Creation {
        Creation(id: id, kind: .video, assetId: nil, createdAt: 100, updatedAt: 200, recipeJSON: json)
    }

    /// Every row a build before drafts wrote came from an export, so the
    /// migration that adds the export date gives each one its edit date.
    @Test func existingRowsBecomeExported() throws {
        let queue = try DatabaseQueue()
        var migrator = AppDatabase.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v28-captionKeywordMirror")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO creations (id, kind, assetId, createdAt, updatedAt, recipeJSON)
                VALUES ('old-video', 'video', 'asset-1', 10, 20, '{}'),
                       ('old-collage', 'collage', NULL, 30, 40, '{}')
                """)
        }
        try migrator.migrate(queue)
        let rows = try queue.read { db in try Creation.fetchAll(db) }
            .reduce(into: [String: Creation]()) { $0[$1.id] = $1 }
        #expect(rows["old-video"]?.exportedAt == 20)
        #expect(rows["old-collage"]?.exportedAt == 40)
        #expect(rows["old-video"]?.isDraft == false)
    }

    /// FS-12.18 AC-10: a draft from an older build — none of the keys added
    /// since — reads back as a draft whose recipe opens.
    @Test func oldDraftMissingNewKeysOpens() throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        try store.saveDraft(draftRow("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"photo"},{"id":"\(clipB)","assetID":"b","kind":"photo"}]}
        """))
        let row = try #require(try store.fetch(id: "draft-1"))
        #expect(row.isDraft)
        let recipe = try #require(row.videoRecipe)
        #expect(recipe.clips.map(\.assetID) == ["a", "b"])
        #expect(row.sourceAssetIds == ["a", "b"])
    }

    /// FS-12.18 AC-10: one clip that cannot be read costs that clip; the
    /// draft opens in the studio with the others, and no error.
    @Test func oneBrokenClipKeepsTheDraft() throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        try store.saveDraft(draftRow("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"photo"},
                  {"id":"\(clipB)","assetID":"b"},
                  {"id":"\(clipC)","assetID":"c","kind":"photo","photoDuration":5}],
         "overlays":[{"start":1}]}
        """))
        let row = try #require(try store.fetch(id: "draft-1"))
        #expect(row.sourceAssetIds == ["a", "c"])
        let dependencies = AppDependencies.preview()
        let model = VideoStudioModel(
            photos: [], mode: .multiClip, service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary, overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages, creationStore: store, restoring: row
        )
        #expect(model.recipe.clips.map(\.assetID) == ["a", "c"])
        #expect(model.recipe.clips[1].photoDuration == 5)
        #expect(model.errorMessage == nil)
    }

    /// Saving a draft over an exported row keeps it exported, keeps its video
    /// and its creation date: an edit after an export is the same project.
    @Test func savingADraftKeepsTheExport() throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        var exported = draftRow("{}", id: "p")
        exported.assetId = "video-asset"
        exported.exportedAt = 300
        try store.upsert(exported)
        try store.saveDraft(Creation(id: "p", kind: .video, assetId: nil, createdAt: 900, updatedAt: 950, recipeJSON: "{\"clips\":[]}"))
        let row = try #require(try store.fetch(id: "p"))
        #expect(row.exportedAt == 300)
        #expect(row.assetId == "video-asset")
        #expect(row.createdAt == 100)
        #expect(row.updatedAt == 950)
        #expect(row.recipeJSON == "{\"clips\":[]}")
    }
}
