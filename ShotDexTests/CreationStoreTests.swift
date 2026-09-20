import Foundation
import Testing
@testable import ShotDex

/// The table that makes "open it again and keep editing" possible: a recipe
/// has to survive the round trip, and re-exporting has to update one row
/// rather than grow a second.
@Suite @MainActor struct CreationStoreTests {
    private func makeStore() throws -> CreationStore {
        CreationStore(database: try AppDatabase.makeEmpty())
    }

    private func sampleCollage() -> CollageRecipe {
        CollageRecipe(
            templateID: "two-up",
            aspectRatio: 0.8,
            aspectPreset: .fourFive,
            gutter: 0.03,
            cells: [
                CollageCell(assetID: "A", contentScale: 1.4, caption: "Left"),
                CollageCell(assetID: "B"),
            ]
        )
    }

    // MARK: Recipe round trip

    @Test func aCollageRecipeSurvivesEncodingAndComesBackIdentical() throws {
        let recipe = sampleCollage()
        let creation = try Creation.collage(recipe: recipe, assetId: "OUT")
        #expect(creation.collageRecipe == recipe)
        #expect(creation.kind == .collage)
        #expect(creation.videoRecipe == nil, "a collage row must not decode as a video")
    }

    @Test func aVideoRecipeSurvivesEncodingAndComesBackIdentical() throws {
        var recipe = VideoProjectRecipe(clips: [
            VideoClip(assetID: "A", kind: .photo),
            VideoClip(assetID: "B", kind: .video),
        ])
        recipe.clips[1].trimStart = 1.5
        recipe.clips[1].speed = 2
        recipe.syncTransitionsWithClips()
        recipe.transitions[0] = .defaultCrossfade
        recipe.musicTracks = [MusicTrack(source: .bundled(id: "calm"))]
        recipe.aspect = .r9x16

        let creation = try Creation.video(recipe: recipe, assetId: "OUT")
        #expect(creation.videoRecipe == recipe)
        #expect(creation.collageRecipe == nil)
    }

    /// The clip ids have to come back unchanged, because `load()` keys the
    /// resolved sources by them — a reopened video with new ids would show an
    /// empty timeline.
    @Test func clipIdentitySurvivesTheRoundTrip() throws {
        let recipe = VideoProjectRecipe(clips: [VideoClip(assetID: "A", kind: .video)])
        let creation = try Creation.video(recipe: recipe, assetId: nil)
        #expect(creation.videoRecipe?.clips.first?.id == recipe.clips[0].id)
    }

    @Test func sourceAssetIdsComeFromTheRecipeInOrder() throws {
        let collage = try Creation.collage(recipe: sampleCollage(), assetId: nil)
        #expect(collage.sourceAssetIds == ["A", "B"])

        let video = try Creation.video(
            recipe: VideoProjectRecipe(clips: [
                VideoClip(assetID: "X", kind: .photo),
                VideoClip(assetID: "Y", kind: .video),
            ]),
            assetId: nil
        )
        #expect(video.sourceAssetIds == ["X", "Y"])
    }

    /// An empty slot contributes no source. Reopening then asks for two
    /// photos, not three, and the screen's "some photos are missing" check
    /// stays honest.
    @Test func anEmptyCollageSlotIsNotASource() throws {
        var recipe = sampleCollage()
        recipe.cells.append(CollageCell(assetID: nil))
        let creation = try Creation.collage(recipe: recipe, assetId: nil)
        #expect(creation.sourceAssetIds == ["A", "B"])
    }

    /// A recipe this build can no longer read is a creation that can still be
    /// listed — it must not crash or come back as an empty collage.
    @Test func unreadableRecipeJSONDecodesToNil() {
        let creation = Creation(
            kind: .collage,
            assetId: "OUT",
            createdAt: 1,
            updatedAt: 1,
            recipeJSON: "{\"whatIsThis\": true}"
        )
        #expect(creation.collageRecipe == nil)
        #expect(creation.sourceAssetIds.isEmpty)
    }

    // MARK: Store

    @Test func upsertThenFetchReturnsTheCreation() throws {
        let store = try makeStore()
        let creation = try Creation.collage(recipe: sampleCollage(), assetId: "OUT")
        try store.upsert(creation)

        let all = try store.fetchAllOrdered()
        #expect(all.count == 1)
        #expect(all.first?.id == creation.id)
        #expect(all.first?.collageRecipe == sampleCollage())
        #expect(try store.count() == 1)
    }

    @Test func theListIsMostRecentlyEditedFirst() throws {
        let store = try makeStore()
        try store.upsert(
            Creation(kind: .collage, assetId: nil, createdAt: 100, updatedAt: 100, recipeJSON: "{}")
        )
        try store.upsert(
            Creation(kind: .video, assetId: nil, createdAt: 50, updatedAt: 300, recipeJSON: "{}")
        )
        #expect(try store.fetchAllOrdered().map(\.kind) == [.video, .collage])
    }

    /// Re-exporting an edit is the same creation with a new output, so the row
    /// is updated and its original `createdAt` is kept — otherwise editing a
    /// collage twice leaves three rows for one collage.
    @Test func reExportingUpdatesTheSameRowAndKeepsItsCreatedAt() throws {
        let store = try makeStore()
        let first = try Creation.collage(
            recipe: sampleCollage(), assetId: "OUT-1", createdAt: 1_000, now: 1_000
        )
        try store.upsert(first)

        var edited = sampleCollage()
        edited.gutter = 0.05
        let second = try Creation.collage(
            recipe: edited, assetId: "OUT-2", id: first.id, createdAt: 9_999, now: 2_000
        )
        try store.upsert(second)

        let all = try store.fetchAllOrdered()
        #expect(all.count == 1, "one collage, one row")
        #expect(all.first?.assetId == "OUT-2")
        #expect(all.first?.createdAt == 1_000, "the original creation time survives a re-export")
        #expect(all.first?.updatedAt == 2_000)
        #expect(all.first?.collageRecipe?.gutter == 0.05)
    }

    @Test func deleteRemovesOneRow() throws {
        let store = try makeStore()
        let creation = try Creation.collage(recipe: sampleCollage(), assetId: nil)
        try store.upsert(creation)
        try store.delete(id: creation.id)
        #expect(try store.count() == 0)
    }

    /// Deleting the exported photo must not take the recipe with it: the
    /// photos it was built from are usually still there, and redoing the
    /// export is exactly what the row is for.
    @Test func aMissingExportClearsTheAssetButKeepsTheCreation() throws {
        let store = try makeStore()
        let kept = try Creation.collage(recipe: sampleCollage(), assetId: "STILL-HERE")
        let gone = try Creation.collage(recipe: sampleCollage(), assetId: "DELETED")
        try store.upsert(kept)
        try store.upsert(gone)

        try store.clearMissingAssets(existingAssetIds: ["STILL-HERE"])

        let all = try store.fetchAllOrdered()
        #expect(all.count == 2)
        #expect(all.first(where: { $0.id == kept.id })?.assetId == "STILL-HERE")
        #expect(all.first(where: { $0.id == gone.id })?.assetId == nil)
        #expect(all.first(where: { $0.id == gone.id })?.collageRecipe == sampleCollage())
    }
}
