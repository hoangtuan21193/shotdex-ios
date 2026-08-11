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

    /// Resolves every clip's media. Videos may hit iCloud — the model shows
    /// its loading phase for the whole pass. A clip whose media can't load is
    /// simply absent from the result (the builder skips it).
    func loadSources(for clips: [VideoClip]) async -> LoadedSources {
        var loaded = LoadedSources()
        for clip in clips {
            guard let asset = PhotoLibraryService.fetchAssets(ids: [clip.assetID]).first else { continue }
            switch clip.kind {
            case .photo:
                loaded.sources[clip.id] = .photo(
                    assetID: clip.assetID,
                    pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
                )
            case .freeze:
                // A frame lifted out of the source video at load time.
                guard let avAsset = await PhotoLibraryService.requestAVAsset(for: asset),
                      let image = await Self.extractFrame(
                          from: avAsset, at: clip.freezeSourceTime ?? 0
                      )
                else { continue }
                loaded.sources[clip.id] = .freeze(image: image, pixelSize: image.extent.size)
            case .video:
                guard let avAsset = await PhotoLibraryService.requestAVAsset(for: asset) else { continue }
                do {
                    let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                    guard let videoTrack = videoTracks.first else { continue }
                    let audioTrack = try await avAsset.loadTracks(withMediaType: .audio).first
                    let (naturalSize, preferredTransform) = try await videoTrack.load(
                        .naturalSize, .preferredTransform
                    )
                    let duration = try await avAsset.load(.duration).seconds
                    loaded.sources[clip.id] = .video(
                        asset: avAsset,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack,
                        duration: duration,
                        naturalSize: naturalSize,
                        preferredTransform: preferredTransform
                    )
                    loaded.durations[clip.id] = duration
                } catch {
                    continue
                }
            }
        }
        return loaded
    }

    /// A single frame out of a source video, oriented, for a freeze clip.
    /// Zero tolerance so the held frame is exactly the one under the playhead.
    static func extractFrame(from avAsset: AVAsset, at seconds: Double) async -> CIImage? {
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
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

    /// The bundled or imported music behind a selection, with its audio track
    /// and duration loaded for the builder.
    ///
    /// The `asset` is returned alongside the track deliberately: `AVAssetTrack`
    /// does not retain its `AVAsset`, and `insertTimeRange(of:)` fails with
    /// AVError -11800 / -12780 if the source asset has been released. The caller
    /// must keep this asset alive across the `VideoCompositionBuilder.build`
    /// call (unlike clip sources, which live in the session's `sources` dict).
    func loadMusic(_ selection: MusicSelection?) async -> (asset: AVURLAsset, track: AVAssetTrack, duration: Double)? {
        guard let selection else { return nil }
        let url: URL?
        switch selection.source {
        case .bundled(let id):
            url = MusicTrackCatalog.track(id: id)?.url
        case .imported(let importedURL, _):
            url = importedURL
        }
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
            let duration = try await asset.load(.duration).seconds
            return (asset, track, duration)
        } catch {
            return nil
        }
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
        let music = await loadMusic(recipe.music)
        let blank = try await blankClipIfNeeded(recipe: recipe, sources: sources)
        let renderSize = previewRenderSize(for: recipe)
        // `music` must stay alive across `build`: the music track's source asset
        // is released otherwise and `insertTimeRange(of:)` fails (-11800/-12780).
        let (composition, layout) = try withExtendedLifetime(music) {
            try VideoCompositionBuilder.build(
                recipe: recipe,
                sources: sources,
                musicSourceTrack: music?.track,
                musicDuration: music?.duration,
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
            stillStore: previewStillStore
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
            stillStore: previewStillStore
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
        let music = await loadMusic(recipe.music)
        let blank = try await blankClipIfNeeded(recipe: recipe, sources: sources)
        let renderSize = recipe.canvasSize()
        // Keep `music` alive across `build` (see `makePreviewItem`): otherwise the
        // music source asset is released and `insertTimeRange` fails -11800.
        let (composition, layout) = try withExtendedLifetime(music) {
            try VideoCompositionBuilder.build(
                recipe: recipe,
                sources: sources,
                musicSourceTrack: music?.track,
                musicDuration: music?.duration,
                blankVideo: blank,
                renderSize: renderSize
            )
        }
        let exportStillStore = StillFrameStore(targetLongEdge: max(renderSize.width, renderSize.height))
        let videoComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe,
            layout: layout,
            stillStore: exportStillStore
        )
        let audioMix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)

        let outputURL = try makeSessionDirectory()
            .appendingPathComponent("ShotDex-Video-\(UUID().uuidString).mp4")

        try await VideoExportWriter.write(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            renderSize: renderSize,
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
