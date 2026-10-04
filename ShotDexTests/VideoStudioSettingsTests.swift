import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// Video Settings in the model (FS-12.10 §5): every change is one undo
/// step, and the 4K gate follows the clips.
@Suite(.serialized) @MainActor
struct VideoStudioSettingsTests {
    /// A library of photos whose sizes the test names.
    struct Library: VideoSourceLoading {
        let sizes: [String: CGSize]
        func items(for ids: [String]) async -> [String: VideoSourceItem] {
            var items: [String: VideoSourceItem] = [:]
            for id in ids {
                guard let size = sizes[id] else { continue }
                items[id] = VideoSourceItem(
                    original: OriginalItem(id: id, filename: "\(id).jpg", photo: PixelSize(width: Int(size.width), height: Int(size.height))),
                    isVideo: false, pixelSize: size, duration: 0
                )
            }
            return items
        }
        func localAVAsset(for id: String) async -> AVAsset? { nil }
    }

    /// AC-6: a project of 4K photos at 4K; adding a 1920×1080 photo drops
    /// it to 1080p, and one Undo takes the photo back and 4K with it.
    @Test func addingA1080ClipDropsTo1080pInOneUndo() async throws {
        let clips = VideoStudioModelFixture.photoClips(2)
        let model = VideoStudioModelFixture.model(clips: clips, configure: { $0.resolution = .uhd4K }) { service in
            service.sourceLoader = Library(sizes: ["Small": CGSize(width: 1920, height: 1080)])
        }
        defer { model.close() }
        for clip in model.recipe.clips {
            model.sources[clip.id] = .photo(assetID: clip.assetID, pixelSize: CGSize(width: 4032, height: 3024))
        }
        #expect(model.fourKVerdict == .allowed)
        model.insertMedia([VideoMediaPick(assetID: "Small", kind: .photo)])
        for _ in 0..<300 where model.recipe.resolution == .uhd4K {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.recipe.resolution == .p1080)
        #expect(model.recipe.clips.count == 3)
        #expect(VideoStudioCopy.fourKReason(model.fourKVerdict) == "4K needs 4K clips — 1 of your 3 clips is 1080p.")
        model.undo()
        #expect(model.recipe.clips.count == 2)
        #expect(model.recipe.resolution == .uhd4K)
    }
}
