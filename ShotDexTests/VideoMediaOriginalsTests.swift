import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// FS-12.09 §5 and plan T-3: an original that is only in iCloud comes down
/// through the app's original fetcher into the session's folder before the
/// clip is drawn from it; a download that fails takes the clip back out
/// with the iCloud sentence and leaves no undo step behind.
@Suite(.serialized) @MainActor
struct VideoMediaOriginalsTests {
    /// The library: two items, a photo and a video, neither on this device.
    struct Library: VideoSourceLoading {
        func items(for ids: [String]) async -> [String: VideoSourceItem] {
            var items: [String: VideoSourceItem] = [:]
            for id in ids where id.hasPrefix("Cloud") {
                let isVideo = id.hasSuffix("Video")
                items[id] = VideoSourceItem(
                    original: OriginalItem(id: id, filename: isVideo ? "\(id).mp4" : "\(id).jpg",
                                           photo: PixelSize(width: 640, height: 480)),
                    isVideo: isVideo,
                    pixelSize: CGSize(width: 640, height: 480),
                    duration: isVideo ? 1 : 0
                )
            }
            return items
        }

        /// PhotoKit has nothing to hand over: the bytes are in iCloud.
        func localAVAsset(for id: String) async -> AVAsset? { nil }
    }

    /// The "iCloud" behind the scripted fetcher: writes a red photo or a
    /// one-second video where the download lands.
    struct Cloud: OriginalFetching {
        func probe(_ item: OriginalItem) async -> OriginalAvailability { .inCloud }
        func byteCount(of item: OriginalItem) async -> Int64? { nil }
        func fetch(_ item: OriginalItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            if item.filename.hasSuffix(".mp4") {
                try await VideoExportFixtures.writeVideo(width: 640, height: 480, seconds: 1, to: url)
            } else {
                try VideoExportFixtures.writePhoto(width: 640, height: 480, red: 0.9, green: 0.1, blue: 0.1, to: url)
            }
        }
    }

    private func service(_ script: String) -> VideoStudioService {
        let service = VideoExportFixtures.service()
        service.sourceLoader = Library()
        service.originalFetcher = FakeOriginalFetcher(
            script: FakeOriginalFetcher.Script(script), base: Cloud()
        )
        return service
    }

    /// An in-iCloud photo is downloaded once and drawn from the file: the
    /// export of a one-photo project is the downloaded red, not black.
    @Test func inCloudPhotoReadsFromTheDownloadedFile() async throws {
        let service = service("cloud=all,seconds=0.1")
        defer { service.cleanupSession() }
        var clip = VideoClip(assetID: "CloudPhoto", kind: .photo)
        clip.photoDuration = 1
        let loaded = await service.loadSources(for: [clip])
        let file = try #require(service.downloadedFiles["CloudPhoto"])
        #expect(FileManager.default.fileExists(atPath: file.path))
        guard case .photo = loaded.sources[clip.id] else {
            Issue.record("the photo should load from its downloaded original")
            return
        }
        let url = try await service.export(
            recipe: VideoProjectRecipe(clips: [clip]), sources: loaded.sources, progress: { _ in }
        )
        let frame = try await VideoExportFixtures.frame(of: url, at: 0.5)
        let middle = ((frame.height / 2) * frame.width + frame.width / 2) * 4
        #expect(frame.bytes[middle] > 200 && frame.bytes[middle + 1] < 60)
    }

    /// An in-iCloud video opens from its downloaded file.
    @Test func inCloudVideoOpensFromTheDownloadedFile() async throws {
        let service = service("cloud=all,seconds=0.1")
        defer { service.cleanupSession() }
        let clip = VideoClip(assetID: "CloudVideo", kind: .video)
        let loaded = await service.loadSources(for: [clip])
        guard case .video(let asset, _, _, let duration, _, _) = loaded.sources[clip.id] else {
            Issue.record("the video should open from its downloaded original")
            return
        }
        #expect((asset as? AVURLAsset)?.url == service.downloadedFiles["CloudVideo"])
        #expect(abs(duration - 1) < 0.05)
    }

    /// AC-10: the sample project, a video only in iCloud tapped with no
    /// network (the download fails): the project is back to its five
    /// clips, the iCloud sentence is shown, and Undo has no empty step.
    @Test func offlineVideoIsLeftOutWithMessage() async throws {
        let recipe = VideoStudioModelFixture.mediaSampleRecipe()
        let model = VideoStudioModelFixture.model(
            clips: recipe.clips,
            configure: { $0 = recipe },
            configureService: { service in
                service.sourceLoader = Library()
                service.originalFetcher = FakeOriginalFetcher(
                    script: FakeOriginalFetcher.Script("cloud=all,seconds=0.1,fail=1"), base: Cloud()
                )
            }
        )
        defer { model.close() }
        // The sample's own clips stand as gaps (no PhotoKit here), so the
        // preview still builds and its errors do not cover the one under test.
        for clip in model.recipe.clips { model.sources[clip.id] = .unavailable(assetID: clip.assetID) }
        let couldUndo = model.canUndo
        let original = model.recipe
        model.seek(to: 8.4)
        model.insertMedia([VideoMediaPick(assetID: "CloudVideo", kind: .video, duration: 1)])
        #expect(model.recipe.clips.count == 7)
        for _ in 0..<500 where model.errorMessage == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.errorMessage?.hasPrefix("One clip couldn't be loaded") == true, "\(model.errorMessage ?? "nil")")
        // Taken back whole — Coast is one clip again — and not a step.
        #expect(model.recipe == original)
        #expect(model.recipe.clips.count == 5)
        #expect(model.canUndo == couldUndo)
        #expect(!model.canRedo)
        #expect(model.currentTime == 8.4)
        #expect(model.unavailableClipIDs.isEmpty == false)
        #expect(model.unavailableClipIDs.isSubset(of: Set(model.recipe.clips.map(\.id))))
    }
}
