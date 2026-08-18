import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// A clip's loaded media, resolved once per session by `VideoStudioService`.
enum VideoClipSource: @unchecked Sendable {
    case video(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        duration: Double,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    )
    case photo(assetID: String, pixelSize: CGSize)
    /// A frame lifted out of a source video at load time — drawn as a still
    /// (no track samples), so it reuses the photo backbone path.
    case freeze(image: CIImage, pixelSize: CGSize)

    var duration: Double? {
        if case .video(_, _, _, let duration, _, _) = self { return duration }
        return nil
    }

    /// Photo and freeze clips both render as stills on the blank backbone.
    var isStill: Bool {
        switch self {
        case .video: false
        case .photo, .freeze: true
        }
    }
}

/// Assembles the one `AVMutableComposition` both the preview player and the
/// export session run. All timing converts to CMTime at timescale 600 from
/// the same boundary list, so instruction ranges tile `[0, total)` exactly —
/// AVFoundation rejects video compositions with gaps or overlaps, and
/// accumulated-Double CMTimes are the classic way to earn that rejection.
enum VideoCompositionBuilder {
    static let timescale: CMTimeScale = 600

    /// Everything the cheap rebuild tiers need, captured at build time:
    /// instruction skeletons (video-composition tier: filter/overlay edits
    /// swap the recipe over the same skeletons) and the audio track layout
    /// (audio-mix tier: volume edits rebuild ramps only).
    struct Layout: @unchecked Sendable {
        /// A source clip's identity + placement timing. The clip's *effect* is
        /// deliberately not frozen in here — `videoComposition()` looks it up
        /// from the fresh recipe by `clipID`, so effect edits stay in the
        /// cheap video-composition tier.
        struct SegmentClip {
            let clipIndex: Int
            let clipID: UUID
            /// Placement start/duration in timeline seconds — a clip split
            /// across passthrough and fade segments animates continuously.
            let start: Double
            let duration: Double
        }
        struct Segment {
            let timeRange: CMTimeRange
            let front: VideoCompositionInstruction.Source
            let frontClip: SegmentClip
            let back: VideoCompositionInstruction.Source?
            let backClip: SegmentClip?
            let fadeStart: Double
            let fadeDuration: Double
            /// `.none` on passthrough segments.
            let transitionKind: VideoTransitionKind
        }
        struct ClipAudio {
            let clipID: UUID
            let trackID: CMPersistentTrackID
            let range: CMTimeRange
        }
        /// One entry per music track that made it into the composition, with the
        /// window it actually occupies — the mix offsets its fade ramps by
        /// `insertAt`.
        struct MusicAudio {
            let musicID: UUID
            let trackID: CMPersistentTrackID
            let insertAt: Double
            let duration: Double
        }
        var segments: [Segment] = []
        var clipAudio: [ClipAudio] = []
        var musicAudio: [MusicAudio] = []
        var totalDuration: Double = 0
        var renderSize: CGSize = .zero
    }

    static func build(
        recipe: VideoProjectRecipe,
        sources: [UUID: VideoClipSource],
        musicSources: [UUID: (track: AVAssetTrack, duration: Double)],
        blankVideo: (track: AVAssetTrack, duration: Double)?,
        renderSize: CGSize
    ) throws -> (composition: AVMutableComposition, layout: Layout) {
        let clips = recipe.clips.filter { sources[$0.id] != nil }
        guard !clips.isEmpty else { throw VideoBuildError.emptyProject }

        // Filtering can drop clips, so re-derive the boundary list against
        // the clips that actually made it in.
        var normalized = recipe
        normalized.clips = clips
        normalized.syncTransitionsWithClips()
        let transitions = normalized.transitions

        let durations = clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(
            requested: transitions.map(\.requestedOverlap),
            durations: durations
        )
        let placements = VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
        let total = VideoTimelineMath.totalDuration(durations: durations, overlaps: overlaps)

        let composition = AVMutableComposition()
        guard
            let videoTrackA = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let videoTrackB = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrackA = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrackB = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw VideoBuildError.cannotBuild }

        var layout = Layout()
        layout.totalDuration = total
        layout.renderSize = renderSize

        // Per clip: front source for the instructions + media into A/B tracks.
        var frontSources: [VideoCompositionInstruction.Source] = []
        for (index, clip) in clips.enumerated() {
            guard let source = sources[clip.id] else { continue }
            let videoTrack = index.isMultiple(of: 2) ? videoTrackA : videoTrackB
            let audioTrack = index.isMultiple(of: 2) ? audioTrackA : audioTrackB
            let at = time(placements[index].start)
            let clipRange = CMTimeRange(
                start: at,
                end: time(placements[index].end)
            )

            switch source {
            case .photo(let assetID, let pixelSize):
                // A photo segment needs real samples on its track — a track
                // made only of empty ranges contributes no duration and the
                // player stops at 0. The blank backbone clip is inserted and
                // stretched to the photo's window; the compositor draws the
                // still and never reads these pixels.
                try insertStillBackbone(into: videoTrack, at: at, clipRange: clipRange, blankVideo: blankVideo)
                frontSources.append(.still(
                    assetID: assetID,
                    fitRect: VideoGeometry.stillFitRect(imageSize: pixelSize, renderSize: renderSize)
                ))
            case .freeze(let image, let pixelSize):
                // Same backbone as a photo, but the still is already loaded.
                try insertStillBackbone(into: videoTrack, at: at, clipRange: clipRange, blankVideo: blankVideo)
                frontSources.append(.stillImage(
                    image: image,
                    fitRect: VideoGeometry.stillFitRect(imageSize: pixelSize, renderSize: renderSize)
                ))
            case .video(_, let sourceVideo, let sourceAudio, let duration, let naturalSize, let preferredTransform):
                let trimmed = VideoTimelineMath.clampedTrim(
                    start: clip.trimStart,
                    end: clip.trimEnd ?? duration,
                    sourceDuration: duration
                )
                let sourceRange = CMTimeRange(
                    start: time(trimmed.start),
                    end: time(trimmed.end)
                )
                try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: at)
                // Speed: scale the inserted source range onto its (shorter/
                // longer) timeline slot. The placement math already sized the
                // slot from `effectiveDuration`, so scaling to `clipRange`
                // keeps the track samples aligned with the instruction ranges.
                if clip.speed != 1 {
                    videoTrack.scaleTimeRange(
                        CMTimeRange(start: at, duration: sourceRange.duration),
                        toDuration: clipRange.duration
                    )
                }
                if let sourceAudio {
                    try audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: at)
                    if clip.speed != 1 {
                        audioTrack.scaleTimeRange(
                            CMTimeRange(start: at, duration: sourceRange.duration),
                            toDuration: clipRange.duration
                        )
                    }
                    layout.clipAudio.append(Layout.ClipAudio(
                        clipID: clip.id,
                        trackID: audioTrack.trackID,
                        range: CMTimeRange(start: at, duration: clipRange.duration)
                    ))
                }
                frontSources.append(.track(
                    id: videoTrack.trackID,
                    transform: VideoGeometry.fitTransform(
                        naturalSize: naturalSize,
                        preferredTransform: preferredTransform,
                        quarterTurns: recipe.quarterTurns,
                        renderSize: renderSize
                    )
                ))
            }
        }

        // Music beds: one dedicated track each, so overlapping beds mix instead
        // of fighting over a single track's timeline.
        for music in recipe.musicTracks {
            guard let source = musicSources[music.id] else { continue }
            guard let placement = VideoTimelineMath.musicPlacement(
                start: music.start,
                trimStart: music.trimStart,
                trimEnd: music.trimEnd,
                sourceDuration: music.sourceDuration ?? source.duration,
                totalDuration: total
            ) else { continue }
            guard let musicTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            try musicTrack.insertTimeRange(
                CMTimeRange(
                    start: time(placement.sourceStart),
                    end: time(placement.sourceStart + placement.duration)
                ),
                of: source.track,
                at: time(placement.insertAt)
            )
            layout.musicAudio.append(Layout.MusicAudio(
                musicID: music.id,
                trackID: musicTrack.trackID,
                insertAt: placement.insertAt,
                duration: placement.duration
            ))
        }

        layout.segments = makeSegments(
            placements: placements,
            overlaps: overlaps,
            transitions: transitions,
            clips: clips,
            frontSources: frontSources,
            total: total
        )
        return (composition, layout)
    }

    /// Instructions from the stored skeletons + a fresh recipe snapshot —
    /// the filter/overlay rebuild tier.
    static func videoComposition(
        recipe: VideoProjectRecipe,
        layout: Layout,
        stillStore: StillFrameStore,
        bakesOverlays: Bool
    ) -> AVMutableVideoComposition {
        let renderRecipe = VideoRenderRecipe(
            recipe: recipe,
            renderSize: layout.renderSize,
            totalDuration: layout.totalDuration,
            bakesOverlays: bakesOverlays
        )
        // Effects come from the FRESH recipe, not the layout: an effect edit
        // swaps the video composition without rebuilding the AVComposition.
        let effectByClipID = Dictionary(
            recipe.clips.map { ($0.id, $0.effect) },
            uniquingKeysWith: { first, _ in first }
        )
        func timing(_ clip: Layout.SegmentClip) -> VideoCompositionInstruction.ClipRenderTiming {
            VideoCompositionInstruction.ClipRenderTiming(
                clipIndex: clip.clipIndex,
                start: clip.start,
                duration: clip.duration,
                effect: effectByClipID[clip.clipID] ?? .none
            )
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = VideoFrameCompositor.self
        videoComposition.renderSize = layout.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = layout.segments.map { segment in
            VideoCompositionInstruction(
                timeRange: segment.timeRange,
                front: segment.front,
                frontClip: timing(segment.frontClip),
                back: segment.back,
                backClip: segment.backClip.map(timing),
                fadeStart: segment.fadeStart,
                fadeDuration: segment.fadeDuration,
                transitionKind: segment.transitionKind,
                recipe: renderRecipe,
                stillStore: stillStore
            )
        }
        return videoComposition
    }

    /// Volume ramps from the recipe over the stored track layout — the
    /// audio-only rebuild tier (assigning a new mix never interrupts playback).
    static func audioMix(recipe: VideoProjectRecipe, layout: Layout) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        var parameters: [AVMutableAudioMixInputParameters] = []

        let master = max(0, recipe.masterVolume)
        let mutedClipIDs = Set(recipe.clips.filter(\.isMuted).map(\.id))
        var byTrack: [CMPersistentTrackID: [Layout.ClipAudio]] = [:]
        for clipAudio in layout.clipAudio {
            byTrack[clipAudio.trackID, default: []].append(clipAudio)
        }
        for (trackID, clipRanges) in byTrack {
            let params = AVMutableAudioMixInputParameters()
            params.trackID = trackID
            for clipAudio in clipRanges {
                let volume = mutedClipIDs.contains(clipAudio.clipID)
                    ? 0
                    : Float(recipe.videoVolume * master)
                params.setVolumeRamp(
                    fromStartVolume: volume,
                    toEndVolume: volume,
                    timeRange: clipAudio.range
                )
            }
            parameters.append(params)
        }

        let musicByID = Dictionary(
            recipe.musicTracks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in layout.musicAudio {
            guard let music = musicByID[entry.musicID] else { continue }
            let params = AVMutableAudioMixInputParameters()
            params.trackID = entry.trackID
            // Ramps come back relative to the track's own window, so shift them
            // onto the timeline by where the track was inserted.
            let ramps = VideoTimelineMath.musicRamps(
                total: entry.duration,
                volume: music.volume,
                fadeIn: music.fadeIn,
                fadeOut: music.fadeOut
            )
            for ramp in ramps {
                params.setVolumeRamp(
                    fromStartVolume: Float(ramp.fromVolume * master),
                    toEndVolume: Float(ramp.toVolume * master),
                    timeRange: CMTimeRange(
                        start: time(entry.insertAt + ramp.start),
                        end: time(entry.insertAt + ramp.start + ramp.duration)
                    )
                )
            }
            parameters.append(params)
        }

        mix.inputParameters = parameters
        return mix
    }

    // MARK: - Internals

    /// The shared blank-backbone insert for still (photo / freeze) clips: real
    /// samples the player can clock against, scaled to the still's window.
    private static func insertStillBackbone(
        into videoTrack: AVMutableCompositionTrack,
        at: CMTime,
        clipRange: CMTimeRange,
        blankVideo: (track: AVAssetTrack, duration: Double)?
    ) throws {
        if let blankVideo {
            let sourceRange = CMTimeRange(start: .zero, end: time(blankVideo.duration))
            try videoTrack.insertTimeRange(sourceRange, of: blankVideo.track, at: at)
            videoTrack.scaleTimeRange(
                CMTimeRange(start: at, duration: sourceRange.duration),
                toDuration: clipRange.duration
            )
        } else {
            videoTrack.insertEmptyTimeRange(clipRange)
        }
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(value: CMTimeValue((seconds * Double(timescale)).rounded()), timescale: timescale)
    }

    /// Segments tiling `[0, total)`: passthrough windows over the topmost
    /// clip, crossfade windows over the two clips that coexist. Boundaries
    /// come from one sorted list so adjacent CMTimeRanges share exact values.
    private static func makeSegments(
        placements: [VideoTimelineMath.Placement],
        overlaps: [Double],
        transitions: [VideoBoundaryTransition],
        clips: [VideoClip],
        frontSources: [VideoCompositionInstruction.Source],
        total: Double
    ) -> [Layout.Segment] {
        guard !placements.isEmpty, frontSources.count == placements.count else { return [] }
        let fades = VideoTimelineMath.crossfades(placements: placements, overlaps: overlaps)

        func segmentClip(_ index: Int) -> Layout.SegmentClip {
            Layout.SegmentClip(
                clipIndex: index,
                clipID: clips[index].id,
                start: placements[index].start,
                duration: placements[index].duration
            )
        }

        // Cut the timeline at every placement boundary (fade windows fall on
        // placement bounds, so they arrive whole). Cutting only at fade edges
        // is not enough: butt-jointed clips would collapse into one segment
        // and `clipIndex(midpoint)` would show a single clip for the lot.
        var cuts: [Double] = [0, total]
        for placement in placements {
            cuts.append(min(max(placement.start, 0), total))
            cuts.append(min(max(placement.end, 0), total))
        }
        cuts.sort()
        var boundaries: [Double] = []
        for cut in cuts where boundaries.last.map({ cut - $0 > 0.0005 }) ?? true {
            boundaries.append(cut)
        }

        var segments: [Layout.Segment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let mid = (start + end) / 2
            if let fade = fades.first(where: { mid >= $0.start && mid < $0.start + $0.duration }) {
                // A fade only exists where the boundary requested an overlap,
                // so its transition is never `.none`; crossfade is the safe
                // defensive default.
                let kind = fade.fromIndex < transitions.count
                    ? transitions[fade.fromIndex].kind
                    : .crossfade
                segments.append(Layout.Segment(
                    timeRange: CMTimeRange(start: time(start), end: time(end)),
                    front: frontSources[fade.fromIndex + 1],
                    frontClip: segmentClip(fade.fromIndex + 1),
                    back: frontSources[fade.fromIndex],
                    backClip: segmentClip(fade.fromIndex),
                    fadeStart: fade.start,
                    fadeDuration: fade.duration,
                    transitionKind: kind
                ))
            } else if let index = VideoTimelineMath.clipIndex(at: mid, placements: placements) {
                segments.append(Layout.Segment(
                    timeRange: CMTimeRange(start: time(start), end: time(end)),
                    front: frontSources[index],
                    frontClip: segmentClip(index),
                    back: nil,
                    backClip: nil,
                    fadeStart: 0,
                    fadeDuration: 0,
                    transitionKind: .none
                ))
            }
        }
        return segments
    }
}

enum VideoBuildError: LocalizedError {
    case emptyProject
    case cannotBuild

    var errorDescription: String? {
        switch self {
        case .emptyProject: String(localized: "There are no clips to build a video from.")
        case .cannotBuild: String(localized: "Couldn't prepare the video composition.")
        }
    }
}
