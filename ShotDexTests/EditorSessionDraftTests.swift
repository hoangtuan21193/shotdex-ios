import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// What the multi-photo run parks as a draft around a Save Changes
/// (FS-03.09b AC-5): leaving a photo just saved must not count it as unsaved
/// again, while an edit made after the save still does.
@MainActor
struct EditorSessionDraftTests {
    private func recipe(exposure: Double, contrast: Double = 0) -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = exposure
        recipe.adjustments.contrast = contrast
        return recipe
    }

    /// Save Changes, then the editor moves on and parks the photo it left:
    /// the same recipe it just wrote is not a draft.
    @Test func leavingASavedPhotoDoesNotParkItAgain() {
        let session = EditorSession(photos: [])
        let saved = recipe(exposure: 0.66)
        session.store(saved, forID: "A")
        session.store(recipe(exposure: 0.4), forID: "B")

        session.markSaved("A", recipe: saved)
        session.store(saved, forID: "A")

        #expect(session.drafts["A"] == nil, "a just-saved photo is not unsaved work")
        #expect(session.draftCount == 1, "Save All counts only photo B")
    }

    /// A change made after the save is a draft again.
    @Test func anEditAfterTheSaveIsADraft() {
        let session = EditorSession(photos: [])
        let saved = recipe(exposure: 0.66)
        session.markSaved("A", recipe: saved)

        let edited = recipe(exposure: 0.66, contrast: 26)
        session.store(edited, forID: "A")
        #expect(session.drafts["A"] == edited)
    }

    /// Resetting a photo saved in this run is a change from what Photos now
    /// holds, not "never touched" — the identity rule is only for photos this
    /// run has not written.
    @Test func resetAfterSaveIsADraft() {
        let session = EditorSession(photos: [])
        session.markSaved("A", recipe: recipe(exposure: 0.66))
        session.store(.identity, forID: "A")
        #expect(session.drafts["A"] == .identity)

        session.store(.identity, forID: "B")
        #expect(session.drafts["B"] == nil, "an untouched photo parks nothing")
    }

    /// Save Copy leaves the photo itself as it was, so its edit stays a draft.
    @Test func saveCopyKeepsTheDraft() {
        let session = EditorSession(photos: [])
        let edit = recipe(exposure: 0.66)
        session.store(edit, forID: "A")
        session.markSaved("copy-of-A")
        session.store(edit, forID: "A")
        #expect(session.drafts["A"] == edit)
    }
}
