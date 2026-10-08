import AVFoundation
import Photos
import UIKit

/// The frame trim (FS-12.17): one edge of the selected clip, moved a frame
/// of the project at a time, nested inside the clip's selection. Nothing in
/// the recipe changes until ✓, which writes the whole trim as **one** undo
/// step; ✕ leaves the project exactly as it was.
extension VideoStudioModel {
    var isFrameTrimming: Bool { frameTrim != nil }

    /// Opens the trim on `edge` of clip `clipID` — the handle held still
    /// for half a second (§3), or the Trim cell on the Duo's inner display
    /// and the iPad. A locked lane has no handles and no trim. Returns
    /// whether the trim opened.
    @discardableResult
    func beginFrameTrim(_ clipID: UUID, edge: VideoEdgeTrimMath.Edge) -> Bool {
        guard !isLaneLocked(.video),
              let index = recipe.clips.firstIndex(where: { $0.id == clipID }),
              index < clipPlacements.count
        else { return false }
        if let frameTrim {
            // Holding the other handle of the clip already in the trim
            // switches the edge; another clip's starts over.
            if frameTrim.clipID == clipID {
                switchFrameTrimEdge(to: edge)
                return true
            }
            commitFrameTrim()
        }
        if selectedClipID != clipID { selectClip(clipID) }
        if isPlaying { togglePlayback() }
        frameTrim = FrameTrimSession(
            clipID: clipID,
            clip: recipe.clips[index],
            placement: clipPlacements[index],
            grid: frameGrid,
            edge: edge
        )
        followFrameTrimEdge()
        return true
    }

    /// The Trim cell (Duo inner, iPad — §3): the edge nearer the playhead.
    @discardableResult
    func beginFrameTrimAtNearerEdge() -> Bool {
        guard let id = selectedClipID,
              let index = recipe.clips.firstIndex(where: { $0.id == id }),
              index < clipPlacements.count
        else { return false }
        let placement = clipPlacements[index]
        let edge: VideoEdgeTrimMath.Edge = abs(currentTime - placement.start) <= abs(placement.end - currentTime)
            ? .leading : .trailing
        return beginFrameTrim(id, edge: edge)
    }

    /// −1 / +1 Frame (§4–5): one frame of the project, when it fits.
    /// Returns whether the edge moved.
    @discardableResult
    func stepFrameTrim(_ count: Int) -> Bool {
        guard var trim = frameTrim, trim.step(by: count) else { return false }
        frameTrim = trim
        followFrameTrimEdge()
        return true
    }

    /// The held edge dragged by `seconds` of timeline since the hold
    /// began (§5): it lands on the grid, as near the finger as the limits
    /// allow. Returns the frame lines crossed and whether it stopped on a
    /// limit — one tick each in the view.
    @discardableResult
    func dragFrameTrim(by seconds: Double, fromFrames start: Int) -> (crossed: Int, hitLimit: Bool) {
        guard var trim = frameTrim else { return (0, false) }
        let target = start + Int((seconds * Double(trim.grid.fps)).rounded())
        let outcome = trim.move(toFrames: target)
        frameTrim = trim
        followFrameTrimEdge()
        return outcome
    }

    func switchFrameTrimEdge(to edge: VideoEdgeTrimMath.Edge) {
        guard var trim = frameTrim, trim.edge != edge else { return }
        trim.switchEdge(to: edge)
        frameTrim = trim
        followFrameTrimEdge()
    }

    /// ✓ (§3): the trim becomes one undo step; the clips after the clip
    /// close up now. The playhead stays on the edge where it landed.
    func commitFrameTrim() {
        guard let trim = frameTrim else { return }
        frameTrim = nil
        isFrameTrimHolding = false
        frameTrimFrames.clear()
        guard trim.changesClip, recipe.clips.contains(where: { $0.id == trim.clipID }) else { return }
        pushUndo()
        recipe = trim.applied(to: recipe)
        markEdited()
        schedulePreviewRebuild()
        if let index = recipe.clips.firstIndex(where: { $0.id == trim.clipID }), index < clipPlacements.count {
            let placement = clipPlacements[index]
            let edge = trim.edge == .leading ? placement.start : placement.end
            seek(to: edge)
        }
    }

    /// ✕ (§3): as if the trim never began — no step, the recipe untouched,
    /// the playhead back on the edge as it was.
    func cancelFrameTrim() {
        guard let trim = frameTrim else { return }
        frameTrim = nil
        isFrameTrimHolding = false
        frameTrimFrames.clear()
        seek(to: trim.originTime(of: trim.edge))
    }

    /// Where a clip's edge is now on the timeline — the trimmed edge's
    /// virtual time while its frame trim is open.
    func clipEdgeTime(_ clipID: UUID, edge: VideoEdgeTrimMath.Edge) -> Double? {
        if let trim = frameTrim, trim.clipID == clipID { return trim.edgeTime(of: edge) }
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }), index < clipPlacements.count else { return nil }
        return edge == .leading ? clipPlacements[index].start : clipPlacements[index].end
    }

    /// VoiceOver's adjust on an edge handle (AC-14): a frame of the
    /// project, written at once as one undo step. Inside an open frame
    /// trim it is that trim's ±1 instead. Returns whether the edge moved.
    @discardableResult
    func stepClipEdge(_ clipID: UUID, edge: VideoEdgeTrimMath.Edge, by count: Int) -> Bool {
        if let trim = frameTrim, trim.clipID == clipID {
            switchFrameTrimEdge(to: edge)
            return stepFrameTrim(count)
        }
        guard !isLaneLocked(.video),
              let index = recipe.clips.firstIndex(where: { $0.id == clipID }),
              index < clipPlacements.count
        else { return false }
        var session = FrameTrimSession(
            clipID: clipID, clip: recipe.clips[index], placement: clipPlacements[index],
            grid: frameGrid, edge: edge
        )
        guard session.step(by: count) else { return false }
        pushUndo()
        recipe = session.applied(to: recipe)
        markEdited()
        schedulePreviewRebuild()
        return true
    }

    /// The footer while trimming (§4): "Trim · Clip 2" over
    /// "0:09.07 · −4 frames" — the Duo's inner display says "−4 f".
    func frameTrimTitle(compact: Bool = false) -> VideoItemTitle.Lines? {
        guard let trim = frameTrim,
              let index = recipe.clips.firstIndex(where: { $0.id == trim.clipID })
        else { return nil }
        let name = VideoItemTitle.clip(recipe.clips[index], index: index).name
        return VideoItemTitle.Lines(
            name: VideoStudioCopy.frameTrimTitle(name),
            detail: VideoFrameGrid.hundredths(trim.edgeTime) + " · " + VideoStudioCopy.frameCount(trim.frames, compact: compact)
        )
    }

    // MARK: Following the edge

    /// The playhead stands on the edge (§5) and the frames around it are
    /// decoded for the loupe and the viewer.
    private func followFrameTrimEdge() {
        guard let trim = frameTrim else { return }
        seek(to: trim.edgeTime)
        frameTrimFrames.update(for: trim, source: sources[trim.clipID], photoLibrary: photoLibrary)
    }
}

/// What the loupe and the viewer draw while a clip's edge is being trimmed:
/// ten frames around the cut and the frame at the edge (FS-12.17 §4–5),
/// decoded off the main actor by `VideoEdgeFrameSource`.
@MainActor
@Observable
final class VideoFrameTrimFrames {
    /// Ten slots, five before the cut and five from it on. Nil is a frame
    /// not decoded yet, or none there.
    private(set) var loupe: [UIImage?] = Array(repeating: nil, count: 10)
    /// The clip's first or last frame, for the viewer.
    private(set) var viewer: UIImage?
    /// The source is not on this device (§10): the loupe draws grey bands
    /// and says Offline; nothing is downloaded to draw it.
    private(set) var isOffline = false

    @ObservationIgnored private var source: VideoEdgeFrameSource?
    @ObservationIgnored private var sourceClipID: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var memoryObserver: NSObjectProtocol?

    /// A loupe frame's longer side: twice the 124pt loupe at 2× — the
    /// strips are slices of the frame, never drawn bigger than that.
    nonisolated static let loupeFrameSide: CGFloat = 496
    /// The viewer's frame: its longer side at most 1280 (§10).
    nonisolated static let viewerFrameSide: CGFloat = 1280

    init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            VideoStudioModel.onMain { self?.purge() }
        }
    }

    func update(for trim: FrameTrimSession, source clipSource: VideoClipSource?, photoLibrary: PhotoLibraryService) {
        task?.cancel()
        switch clipSource {
        case .video(let asset, _, _, _, _, _):
            if sourceClipID != trim.clipID {
                source = VideoEdgeFrameSource(asset: asset)
                sourceClipID = trim.clipID
                loupe = Array(repeating: nil, count: 10)
                viewer = nil
            }
            isOffline = !VideoEdgeFrameSource.isLocal(asset)
            guard !isOffline, let source else {
                loupe = Array(repeating: nil, count: 10)
                return
            }
            let loupeTimes = trim.loupeSourceTimes
            let viewerTime = trim.viewerSourceTime
            task = Task { [weak self] in
                if let viewerTime, let image = await source.frame(at: viewerTime, maximumSide: Self.viewerFrameSide) {
                    guard !Task.isCancelled else { return }
                    self?.viewer = UIImage(cgImage: image)
                }
                var frames: [UIImage?] = []
                for time in loupeTimes {
                    guard !Task.isCancelled else { return }
                    if let time, let image = await source.frame(at: time, maximumSide: Self.loupeFrameSide) {
                        frames.append(UIImage(cgImage: image))
                    } else {
                        frames.append(nil)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.loupe = frames
            }
        case .photo(let assetID, _):
            // A still: every frame is the photo.
            isOffline = false
            guard sourceClipID != trim.clipID || viewer == nil else { return }
            sourceClipID = trim.clipID
            source = nil
            guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: Self.viewerFrameSide, height: Self.viewerFrameSide),
                allowNetwork: false
            ) { [weak self] image in
                guard let self, let image else { return }
                self.viewer = image
                self.loupe = Array(repeating: image, count: 10)
            }
        case .freeze(let image, _, _, _, _):
            isOffline = false
            sourceClipID = trim.clipID
            source = nil
            let still = CIContext().createCGImage(image, from: image.extent).map(UIImage.init(cgImage:))
            viewer = still
            loupe = Array(repeating: still, count: 10)
        case .unavailable, .none:
            isOffline = true
            loupe = Array(repeating: nil, count: 10)
        }
    }

    /// The trim ended: everything decoded goes.
    func clear() {
        task?.cancel()
        task = nil
        loupe = Array(repeating: nil, count: 10)
        viewer = nil
        isOffline = false
        sourceClipID = nil
        let source = source
        self.source = nil
        Task { await source?.purge() }
    }

    private func purge() {
        let source = source
        Task { await source?.purge() }
    }
}
