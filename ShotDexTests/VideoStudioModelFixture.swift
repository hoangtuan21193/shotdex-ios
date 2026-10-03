import Foundation
@testable import ShotDex

/// A Video Studio model over a stored recipe, for the tests that drive the
/// model's own rules — selection, sessions, undo, drafts — without PhotoKit.
///
/// The model is built the way a reopened project is: from a `Creation` row,
/// so the recipe it holds is exactly the one the test wrote. No sources load,
/// so nothing here plays or renders; every rule under test is recipe state.
enum VideoStudioModelFixture {
    /// Video clips of `seconds` each, with their source length already known
    /// (what `load()` would have filled in).
    static func videoClips(_ count: Int, seconds: Double = 10) -> [VideoClip] {
        (0..<count).map { index in
            var clip = VideoClip(assetID: "fixture-video-\(index)", kind: .video)
            clip.sourceDuration = seconds
            clip.trimEnd = seconds
            return clip
        }
    }

    static func photoClips(_ count: Int, seconds: Double = VideoClip.defaultPhotoDuration) -> [VideoClip] {
        (0..<count).map { index in
            var clip = VideoClip(assetID: "fixture-photo-\(index)", kind: .photo)
            clip.photoDuration = seconds
            return clip
        }
    }

    @MainActor
    static func model(
        clips: [VideoClip] = videoClips(3),
        configure: (inout VideoProjectRecipe) -> Void = { _ in },
        creationStore: CreationStore? = nil,
        mode: VideoStudioMode = .multiClip
    ) -> VideoStudioModel {
        var recipe = VideoProjectRecipe(clips: clips)
        recipe.syncTransitionsWithClips()
        configure(&recipe)
        let dependencies = AppDependencies.preview()
        let row = try! Creation.video(recipe: recipe, assetId: nil)
        return VideoStudioModel(
            photos: [],
            mode: mode,
            service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary,
            overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages,
            creationStore: creationStore,
            restoring: row
        )
    }
}
