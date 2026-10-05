import Foundation
import ShotDexKit

/// Save as Look… (FS-12.06c §6b): the whole video's look and grade, cut to
/// what a photo look holds, saved into the My Looks the photo editor uses.
extension VideoStudioModel {
    /// What Save as Look… would save now, and what it would leave out.
    var photoLookCut: VideoPhotoLookCut {
        VideoLookSaving.photoLook(of: recipe)
    }

    /// Saves the cut under `name` with the photo editor's rules: the name
    /// is trimmed, a blank one is refused, a name already in My Looks (any
    /// case) is saved over. The project does not change — no undo step —
    /// and the My Looks shelf comes up with the new look first.
    @discardableResult
    func saveVideoLook(named name: String, into store: LookPresetStore) -> LookPreset? {
        let cut = photoLookCut
        guard !cut.isEmpty, let preset = store.save(cut.recipe, name: name) else { return nil }
        lookShelf = .myLooks
        return preset
    }
}
