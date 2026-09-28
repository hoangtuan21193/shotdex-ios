import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15d AC-47…AC-49 — People. Vision separating real people needs a
/// device (and a photo of mannequins, not faces); what is tested here is
/// everything around it.
struct PeopleMaskTests {

    /// AC-47. Two people: three rows — All People, Person 1, Person 2 —
    /// ordered by area; never more than four person rows.
    @MainActor @Test func onePersonRowPerPerson() {
        #expect(PhotoRenderService.peopleByArea([0: 900, 1: 120, 2: 480]) == [2, 1])
        #expect(PhotoEditorController.peopleRows(count: 2).map(\.title) == ["All People", "Person 1", "Person 2"])
        #expect(PhotoEditorController.peopleRows(count: 7).count == 5)
        #expect(PhotoRenderService.peopleByArea([1: 5, 2: 9, 3: 7, 4: 1, 5: 3]) == [2, 3, 1, 5])
    }

    /// AC-48. A photo with no semantic matte: Hair makes no mask and says
    /// why; Entire Person still can.
    @MainActor @Test func hairIsGatedOnTheMatte() {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        let reason = controller.addPeopleMask(person: 1, part: .hair, available: [])
        #expect(reason == "Needs a Portrait photo taken on iPhone")
        #expect(controller.recipe.masks.isEmpty)

        #expect(controller.addPeopleMask(person: 1, part: .entire, available: []) == nil)
        let component = controller.recipe.masks.first?.components.first
        #expect(component?.kind == .people)
        #expect(component?.personIndex == 1)
        #expect(component?.personPart == nil)
        #expect(controller.addPeopleMask(person: nil, part: .hair, available: [.hair]) == nil)
    }

    /// AC-49. No person found (the simulator's Vision cannot): the notice is
    /// "Couldn't find a person", and the empty mask stays for Undo/Delete.
    @MainActor @Test func noPersonSaysSo() {
        #expect(PhotoEditorController.detectionFailureText(for: .people) == "Couldn't find a person")
        #expect(PhotoPersonPart.hair.needsSemanticMatte && !PhotoPersonPart.eyes.needsSemanticMatte)
    }
}
