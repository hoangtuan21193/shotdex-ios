import AVFoundation
import CoreImage
import Foundation
import Photos

/// The Video Studio's framework-facing service: resolves PHAssets into
/// composition sources, hands the model preview player items and export
/// sessions built from the *same* composition (what you preview is what you
/// export), and saves the finished file to Photos through the app's normal
/// create-index-publish path.
@MainActor
final class VideoStudioService {
    /// Preview compositor cost scales with pixels; 1280 keeps scrubbing
    /// responsive while the export rebuilds at the preset's full size.
    static let previewLongEdge: CGFloat = 1280

    private let importFile: (URL, Bool) async throws -> String
    private let indexNewAsset: (String) async -> Void
    private let publishCreatedAsset: () -> Void
    /// One per session: preview-sized stills. Export builds its own.
    private let previewStillStore = StillFrameStore(targetLongEdge: previewLongEdge)
    private var sessionDirectory: URL?
    /// Server copies on this device by clip id, for a project made from
    /// server photos (FS-17.06 §5b). Empty otherwise.
    private(set) var serverFiles: [String: URL] = [:]

    /// RAWs this iOS build can't read (FS-03.04b §4): one in the project was
    /// taken in with Convert to JPEG, so its still is the embedded preview.
    var unreadableRAWIds: @MainActor () -> Set<String> = { [] }

    /// Where originals that are only in iCloud come down from (FS-12.09 §5):
    /// a clip goes on the timeline at once and its file follows. Nil keeps
    /// every source on PhotoKit's own request.
    var originalFetcher: (any OriginalFetching)?
    /// What the library knows about each item, and its local video. PhotoKit
    /// in the app; a fixture in tests.
    var sourceLoader: any VideoSourceLoading = PhotoKitVideoSourceLoader()
    /// Originals brought down from iCloud this session, by library id.
    private(set) var downloadedFiles: [String: URL] = [:]
    /// At most this many originals download at once, as in Prepare Originals.
    static let maximumConcurrentDownloads = 4

    /// Every still read from a file: server copies and downloaded originals.
    private var stillFiles: [String: URL] {
        serverFiles.merging(downloadedFiles) { server, _ in server }
    }

    /// Points the stills of this session at server copies on disk; an empty
    /// map when the session ends.
    func setServerFiles(_ files: [String: URL]) {
        serverFiles = files
        previewStillStore.setFiles(stillFiles)
    }

    init(
        importFile: @escaping (URL, Bool) async throws -> String,
        indexNewAsset: @escaping (String) async -> Void,
        publishCreatedAsset: @escaping () -> Void
    ) {
        self.importFile = importFile
        self.indexNewAsset = indexNewAsset
        self.publishCreatedAsset = publishCreatedAsset
    }

    // MARK: - Sources

    struct LoadedSources {
        var sources: [UUID: VideoClipSource] = [:]
        /// Clip id → resolved source duration, for seeding trim ranges.
        var durations: [UUID: Double] = [:]
    }

    /// Resolves every clip's media. A clip whose media can't load is simply
    /// absent from the result (the builder skips it), or — media the
    /// library has but cannot hand over — `.unavailable`.
    ///
    /// Originals only in iCloud come down through `originalFetcher` first,
    /// at most four at once, into the session's folder: a photo is then
    /// read from that file, a video opened from it. A download that fails
    /// leaves the clip unavailable. (FS-12.09 §5, plan T-3.)
    ///
    /// `maximumStillSize` caps a freeze frame's decode. The composition
    /// renders into the project's canvas, so a 4K frame lifted out of a 4K
    /// video is downscaled the moment it is drawn — but held at native size
    /// it is ~33MB of decoded image sitting there for the whole session, per
    /// freeze clip. Extracting it at the canvas size costs nothing visible
    /// and roughly quarters that.
    func loadSources(
        for clips: [VideoClip],
        maximumStillSize: CGSize? = nil
    ) async -> LoadedSources {
        var loaded = LoadedSources()
        previewStillStore.setEmbeddedPreviewIds(unreadableRAWIds())
        // One lookup for every clip, not one per clip.
        let libraryIDs = Array(Set(clips.map(\.assetID).filter { serverFiles[$0] == nil }))
        let items = await sourceLoader.items(for: libraryIDs)
        let failedDownloads = await downloadOriginals(of: libraryIDs.compactMap { items[$0] })

        // Photos resolve with no await at all, so they are taken first and in
        // one pass — a project of stills is now ready without waiting behind
        // anything.
        var pending: [(clip: VideoClip, item: VideoSourceItem)] = []
        for clip in clips {
            if clip.kind == .photo, let file = serverFiles[clip.assetID] {
                // A server copy: its oriented size straight from the file.
                let size = PhotoEditOrigin.orientedPixelSize(of: file)
                loaded.sources[clip.id] = .photo(
                    assetID: clip.assetID,
                    pixelSize: CGSize(width: size?.width ?? 0, height: size?.height ?? 0)
                )
                continue
            }
            guard let item = items[clip.assetID] else { continue }
            if clip.kind == .photo {
                loaded.sources[clip.id] = failedDownloads.contains(clip.assetID)
                    ? .unavailable(assetID: clip.assetID)
                    : .photo(assetID: clip.assetID, pixelSize: item.pixelSize)
            } else {
                pending.append((clip, item))
            }
        }

        // The rest are AVFoundation loads. In parallel: the old serial loop
        // paid for every clip's latency one after another.
        let loader = sourceLoader
        let files = downloadedFiles
        await withTaskGroup(of: (UUID, VideoClipSource?, Double?).self) { group in
            for (clip, item) in pending where !failedDownloads.contains(clip.assetID) {
                let file = files[clip.assetID]
                group.addTask {
                    let avAsset: AVAsset? = if let file { AVURLAsset(url: file) } else { await loader.localAVAsset(for: item.original.id) }
                    return await Self.resolve(clip: clip, avAsset: avAsset, maximumStillSize: maximumStillSize)
                }
            }
            for await (id, source, duration) in group {
                if let source { loaded.sources[id] = source }
                if let duration { loaded.durations[id] = duration }
            }
        }
        // Media that would not come down — an iCloud original with no
        // network — stays on the track as an unavailable clip, with the
        // length the library already knows, instead of disappearing
        // (FS-12.04 §7). A clip whose asset is gone from the library has no
        // entry and is still left out.
        for (clip, item) in pending where loaded.sources[clip.id] == nil {
            loaded.sources[clip.id] = .unavailable(assetID: clip.assetID)
            if clip.kind == .video, loaded.durations[clip.id] == nil, item.duration > 0 {
                loaded.durations[clip.id] = item.duration
            }
        }
        return loaded
    }

    /// Probes each item with the network off and downloads the ones only in
    /// iCloud, four at a time. Returns the ids whose download failed.
    private func downloadOriginals(of items: [VideoSourceItem]) async -> Set<String> {
        guard let fetcher = originalFetcher else { return [] }
        let candidates = items.filter { downloadedFiles[$0.original.id] == nil }
        guard !candidates.isEmpty, let directory = try? makeSessionDirectory() else { return [] }
        var inCloud: [VideoSourceItem] = []
        await withTaskGroup(of: (VideoSourceItem, OriginalAvailability).self) { group in
            for item in candidates {
                group.addTask { (item, await fetcher.probe(item.original)) }
            }
            for await (item, availability) in group where availability == .inCloud {
                inCloud.append(item)
            }
        }
        guard !inCloud.isEmpty else { return [] }
        var failed: Set<String> = []
        var fetched: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            var queue = inCloud[...]
            func startNext() {
                guard let item = queue.popFirst() else { return }
                let ext = (item.original.filename as NSString).pathExtension
                let url = directory.appendingPathComponent("original-\(UUID().uuidString)")
                    .appendingPathExtension(ext.isEmpty ? (item.isVideo ? "mov" : "jpg") : ext)
                group.addTask {
                    do {
                        try await fetcher.fetch(item.original, to: url, progress: { _ in })
                        return (item.original.id, url)
                    } catch {
                        try? FileManager.default.removeItem(at: url)
                        return (item.original.id, nil)
                    }
                }
            }
            for _ in 0..<Self.maximumConcurrentDownloads { startNext() }
            for await (id, url) in group {
                if let url { fetched[id] = url } else { failed.insert(id) }
                startNext()
            }
        }
        downloadedFiles.merge(fetched) { _, new in new }
        previewStillStore.setFiles(stillFiles)
        return failed
    }

    /// One non-photo clip's media from its `AVAsset`. Returns the clip's id
    /// so the caller can put the results back in the right place whatever
    /// order they finish in.
    private static func resolve(
        clip: VideoClip,
        avAsset: AVAsset?,
        maximumStillSize: CGSize?
    ) async -> (UUID, VideoClipSource?, Double?) {
        guard let avAsset else { return (clip.id, nil, nil) }
        do {
            switch clip.kind {
            case .photo:
                break
            case .freeze:
                // A frame lifted out of the source video at load time.
                guard let image = await Self.extractFrame(
                    from: avAsset,
                    at: clip.freezeSourceTime ?? 0,
                    maximumSize: maximumStillSize
                ) else { return (clip.id, nil, nil) }
                let videoSize = await Self.orientedVideoSize(avAsset)
                return (clip.id, .freeze(
                    image: image, pixelSize: image.extent.size,
                    asset: avAsset, time: clip.freezeSourceTime ?? 0, videoSize: videoSize
                ), nil)
            case .video:
                let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                guard let videoTrack = videoTracks.first else { return (clip.id, nil, nil) }
                let audioTrack = try await avAsset.loadTracks(withMediaType: .audio).first
                let (naturalSize, preferredTransform) = try await videoTrack.load(
                    .naturalSize, .preferredTransform
                )
                let duration = try await avAsset.load(.duration).seconds
                return (
                    clip.id,
                    .video(
                        asset: avAsset,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack,
                        duration: duration,
                        naturalSize: naturalSize,
                        preferredTransform: preferredTransform
                    ),
                    duration
                )
            }
        } catch {
            return (clip.id, nil, nil)
        }
        return (clip.id, nil, nil)
    }

    /// A video's display size: its track's natural size through its
    /// preferred transform.
    static func orientedVideoSize(_ asset: AVAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return .zero }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Freeze frames lifted again at the export's frame size: the session
    /// lifted them at the canvas size of the day, and a project switched to
    /// 4K afterwards would otherwise upscale them (plan T-6).
    static func freezesLifted(at size: CGSize, in sources: [UUID: VideoClipSource]) async -> [UUID: VideoClipSource] {
        var lifted = sources
        for (id, source) in sources {
            guard case let .freeze(image, _, asset?, time, videoSize) = source,
                  max(image.extent.width, image.extent.height) < max(size.width, size.height) - 1,
                  let fresh = await extractFrame(from: asset, at: time, maximumSize: size)
            else { continue }
            lifted[id] = .freeze(image: fresh, pixelSize: fresh.extent.size, asset: asset, time: time, videoSize: videoSize)
        }
        return lifted
    }

    /// A single frame out of a source video, oriented, for a freeze clip.
    /// Zero tolerance so the held frame is exactly the one under the playhead.
    static func extractFrame(
        from avAsset: AVAsset,
        at seconds: Double,
        maximumSize: CGSize? = nil
    ) async -> CIImage? {
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        if let maximumSize { generator.maximumSize = maximumSize }
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let requested = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: requested).image else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Blank backbone clip

    /// Backbone media for photo clips. `insertEmptyTimeRange` cannot extend a
    /// track that has no real segments, so an all-photo project would report
    /// duration 0 and the player would stop the moment it starts. A tiny
    /// black clip written once per session gives every photo segment real
    /// samples to clock against; the compositor draws the still and never
    /// reads these pixels (`.still` sources require no track).
    private var blankClip: (asset: AVAsset, track: AVAssetTrack, duration: Double)?

    func loadBlankClip() async throws -> (track: AVAssetTrack, duration: Double) {
        if let blankClip { return (blankClip.track, blankClip.duration) }
        let url = try makeSessionDirectory().appendingPathComponent("blank-backbone.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await Self.writeBlankVideo(to: url)
        }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoBuildError.cannotBuild
        }
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw VideoBuildError.cannotBuild }
        blankClip = (asset, track, duration)
        return (track, duration)
    }

    /// A one-second black clip, 720p at 30 fps — a fully-formed H.264 track
    /// (not a 2-frame stub, which `AVAssetExportSession`'s media validator
    /// rejects at export with -12783/-16976). Photo segments insert this and
    /// scale it to the still's duration; a proper GOP survives that scaling.
    private static func writeBlankVideo(to url: URL) async throws {
        let width = 1280, height = 720
        let fps = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoBuildError.cannotBuild }
        writer.startSession(atSourceTime: .zero)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA,
            adaptor.sourcePixelBufferAttributes as CFDictionary?, &buffer
        )
        guard let buffer else { throw VideoBuildError.cannotBuild }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for frame in 0...fps {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(
                value: CMTimeValue(frame), timescale: CMTimeScale(fps)
            ))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(fps), timescale: CMTimeScale(fps)))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? VideoBuildError.cannotBuild
        }
    }

    /// The blank backbone, but only when the project actually has a photo
    /// clip — pure-video projects don't need one.
    private func blankClipIfNeeded(
        recipe: VideoProjectRecipe,
        sources: [UUID: VideoClipSource]
    ) async throws -> (track: AVAssetTrack, duration: Double)? {
        let hasStillClip = recipe.clips.contains { clip in
            sources[clip.id]?.isStill ?? false
        }
        guard hasStillClip else { return nil }
        return try await loadBlankClip()
    }

    /// Audio tracks for the project's music beds, keyed by `MusicTrack.id`.
    ///
    /// `assets` is carried alongside deliberately: `AVAssetTrack` does not retain
    /// its `AVAsset`, and `insertTimeRange(of:)` fails with AVError -11800 /
    /// -12780 if the source asset has been released. The caller must keep the
    /// assets alive across the `VideoCompositionBuilder.build` call (unlike clip
    /// sources, which live in the session's `sources` dict).
    struct LoadedMusic {
        var assets: [AVURLAsset] = []
        var sources: [UUID: (track: AVAssetTrack, duration: Double)] = [:]
    }

    static func url(for source: MusicSource) -> URL? {
        switch source {
        case .bundled(let id): MusicTrackCatalog.track(id: id)?.url
        case .imported(let importedURL, _): importedURL
        }
    }

    func loadMusicSources(_ tracks: [MusicTrack]) async -> LoadedMusic {
        var loaded = LoadedMusic()
        for music in tracks {
            guard let url = Self.url(for: music.source) else { continue }
            let asset = AVURLAsset(url: url)
            do {
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let duration = try await asset.load(.duration).seconds
                loaded.assets.append(asset)
                loaded.sources[music.id] = (track, duration)
            } catch {
                continue
            }
        }
        return loaded
    }

    /// The playable length of a music source, so a freshly added track can seed
    /// its trim window before the first preview rebuild.
    func loadAudioDuration(for source: MusicSource) async -> Double? {
        guard let url = Self.url(for: source) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else {
            return nil
        }
        return duration
    }

    // MARK: - Preview

    struct PreviewBuild {
        let playerItem: AVPlayerItem
        let layout: VideoCompositionBuilder.Layout
    }

    /// A player item over the full pipeline at preview resolution. Called on
    /// structural edits; filter/volume edits use the cheap tiers below.
    func makePreviewItem(
        recipe: VideoProjectRecipe,
        sources: [UUID: VideoClipSource]
    ) async throws -> PreviewBuild {
        let music = await loadMusicSources(recipe.musicTracks)
        let blank = try await blankClipIfNeeded(recipe: recipe, sources: sources)
        let renderSize = previewRenderSize(for: recipe)
        // The music assets must stay alive across `build`: a music track's source
        // asset is released otherwise and `insertTimeRange(of:)` fails
        // (-11800/-12780).
        let (composition, layout) = try withExtendedLifetime(music.assets) {
            try VideoCompositionBuilder.build(
                recipe: recipe,
                sources: sources,
                musicSources: music.sources,
                blankVideo: blank,
                renderSize: renderSize
            )
        }
        // Parity with `VideoExportWriter`: the builder always adds the A/B audio
        // backbone tracks, and a photo-only project leaves them empty. Reading an
        // empty track through an engaged audio mix fails, so drop them.
        for track in composition.tracks(withMediaType: .audio)
        where track.timeRange.duration.seconds <= 0.01 {
            composition.removeTrack(track)
        }
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe,
            layout: layout,
            stillStore: previewStillStore,
            bakesOverlays: false
        )
        item.audioMix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
        return PreviewBuild(playerItem: item, layout: layout)
    }

    /// Filter/adjustment/overlay tier: new instructions over the same
    /// composition, assigned in place.
    func applyVideoComposition(
        recipe: VideoProjectRecipe,
        layout: VideoCompositionBuilder.Layout,
        to item: AVPlayerItem
    ) {
        item.videoComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe,
            layout: layout,
            stillStore: previewStillStore,
            bakesOverlays: false,
            renderSize: previewRenderSize(for: recipe)
        )
    }

    /// Volume/mute/fade tier: a new mix only — playback never interrupts.
    func applyAudioMix(
        recipe: VideoProjectRecipe,
        layout: VideoCompositionBuilder.Layout,
        to item: AVPlayerItem
    ) {
        item.audioMix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
    }

    // MARK: - Export

    /// Builds fresh at the preset's full size and writes to a temp file via an
    /// `AVAssetReader` → `AVAssetWriter` pipeline. `AVAssetExportSession`
    /// refuses a `customVideoCompositorClass` (fails -11838/-16976, whatever
    /// the preset), so the export reads composited frames through the same
    /// `AVVideoComposition` our compositor drives and re-encodes them itself.
    func export(
        recipe: VideoProjectRecipe,
        sources: [UUID: VideoClipSource],
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let renderSize = recipe.canvasSize()
        let sources = await Self.freezesLifted(at: renderSize, in: sources)
        let music = await loadMusicSources(recipe.musicTracks)
        let blank = try await blankClipIfNeeded(recipe: recipe, sources: sources)
        // Keep the music assets alive across `build` (see `makePreviewItem`):
        // otherwise a source asset is released and `insertTimeRange` fails -11800.
        let (composition, layout) = try withExtendedLifetime(music.assets) {
            try VideoCompositionBuilder.build(
                recipe: recipe,
                sources: sources,
                musicSources: music.sources,
                blankVideo: blank,
                renderSize: renderSize
            )
        }
        let exportStillStore = StillFrameStore(
            targetLongEdge: max(renderSize.width, renderSize.height), files: stillFiles,
            embeddedPreviewIds: unreadableRAWIds()
        )
        let videoComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe,
            layout: layout,
            stillStore: exportStillStore,
            bakesOverlays: true,
            frameRate: recipe.frameRate
        )
        let audioMix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)

        let outputURL = try makeSessionDirectory()
            .appendingPathComponent("ShotDex-Video-\(UUID().uuidString).mp4")

        try await VideoExportWriter.write(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            encoding: VideoEncodingSettings.make(for: recipe),
            totalDuration: layout.totalDuration,
            to: outputURL,
            progress: progress
        )
        return outputURL
    }

    /// Photos ingest + direct index + grid refresh — the same closure trio
    /// `PhotoEditingService` uses, so the new video appears before dismissal.
    func saveToPhotos(url: URL) async throws -> String {
        let assetID = try await importFile(url, true)
        await indexNewAsset(assetID)
        publishCreatedAsset()
        try? FileManager.default.removeItem(at: url)
        return assetID
    }

    /// Copies a security-scoped Files pick into the session's temp directory.
    /// Projects are session-ephemeral, so a temp copy is the right lifetime.
    func copyImportedMusic(from pickedURL: URL) throws -> URL {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }
        let destination = try makeSessionDirectory()
            .appendingPathComponent("music-\(UUID().uuidString)")
            .appendingPathExtension(pickedURL.pathExtension.isEmpty ? "m4a" : pickedURL.pathExtension)
        try FileManager.default.copyItem(at: pickedURL, to: destination)
        return destination
    }

    func cleanupSession() {
        downloadedFiles = [:]
        if let sessionDirectory {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        sessionDirectory = nil
    }

    // MARK: - Internals

    private func previewRenderSize(for recipe: VideoProjectRecipe) -> CGSize {
        let full = recipe.canvasSize()
        let scale = Self.previewLongEdge / max(full.width, full.height)
        return CGSize(
            width: (full.width * scale / 2).rounded() * 2,
            height: (full.height * scale / 2).rounded() * 2
        )
    }

    private func makeSessionDirectory() throws -> URL {
        if let sessionDirectory { return sessionDirectory }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexVideo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        sessionDirectory = url
        return url
    }
}

/// One library item as the Video Studio's loader sees it: what the original
/// is called and how big, whether it is a video, and how long.
struct VideoSourceItem: Sendable {
    let original: OriginalItem
    let isVideo: Bool
    let pixelSize: CGSize
    let duration: Double
}

/// The library side of loading clips — a seam, so loading, iCloud originals
/// and failures run in a unit test without PhotoKit.
protocol VideoSourceLoading: Sendable {
    /// What the library knows of each id; an id it no longer has is absent.
    func items(for ids: [String]) async -> [String: VideoSourceItem]
    /// The video as PhotoKit hands it over (which may itself reach iCloud).
    func localAVAsset(for id: String) async -> AVAsset?
}

struct PhotoKitVideoSourceLoader: VideoSourceLoading {
    func items(for ids: [String]) async -> [String: VideoSourceItem] {
        var items: [String: VideoSourceItem] = [:]
        for asset in PhotoLibraryService.fetchAssets(ids: ids) {
            items[asset.localIdentifier] = VideoSourceItem(
                original: OriginalItem(asset: asset),
                isVideo: asset.mediaType == .video,
                pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                duration: asset.duration
            )
        }
        return items
    }

    func localAVAsset(for id: String) async -> AVAsset? {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [id]).first else { return nil }
        return await PhotoLibraryService.requestAVAsset(for: asset)
    }
}
