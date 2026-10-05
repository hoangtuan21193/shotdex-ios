import SwiftUI
import ShotDexKit

/// The multi-track timeline: a pinned ruler, a scrolling lane stack whose centre
/// carries a fixed playhead, and a thin scrollbar. Horizontal scrolling scrubs;
/// vertical scrolling reveals lanes beyond the viewport; playback scrolls; pinch
/// rescales.
struct VideoTimelineView: View {
    @Bindable var model: VideoStudioModel
    /// Decided by `VideoStudioMetrics.stackLayout`: the preview's leftover, never
    /// under `timelineMinimumHeight`.
    let height: CGFloat

    @Environment(\.videoLaneMetrics) private var lanes

    let onAddOverlay: () -> Void
    let onAddMusic: () -> Void
    let onAddMedia: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onTransition: (Int) -> Void
    /// Seconds the viewport is showing, for the project-overview strip the
    /// desk layout draws above the ruler. It lives outside the timeline (it is
    /// a band of the stack, not a lane), but the zoom that decides it is in
    /// here.
    var onVisibleDuration: ((Double) -> Void)?
    /// A zoom the layout imposes for now — the Duo cover's 18pt a second
    /// while a group is selected (FS-12.11 §4). Nil gives back the user's.
    var zoomOverride: CGFloat? = nil

    /// Opens at the window's own zoom (`Lanes.pointsPerSecond`) — set once,
    /// on appear, so a pinch the user made is never taken back.
    @State private var pps: CGFloat = VideoStudioMetrics.Lanes.duo.pointsPerSecond
    @State private var pinchStartPPS: CGFloat = VideoStudioMetrics.Lanes.duo.pointsPerSecond
    @State private var hasAppliedWindowZoom = false
    @State private var dragZones: [TimelineDragZone] = []
    @State private var activeDrag: TimelineActiveDrag?
    /// Where the clip press began, in content points. A reference: the
    /// press's callbacks land before any render could hand back state.
    @State private var pressStartHolder = TimelinePressStart()
    private var pressStart: TimelinePressStart { pressStartHolder }
    @State private var viewportWidth: CGFloat = 393
    @State private var lastHapticSecond = 0
    /// Whether the edge being dragged sat at a limit, or on a snap, on the
    /// last frame — so each gives one tick on arrival.
    @State private var edgeAtLimit = false
    @State private var edgeSnapped = false
    /// Mirrors the lane stack's vertical scroll so the gutter icons stay on
    /// their rows.
    @State private var laneOffsetY: CGFloat = 0

    /// Timeline width plus trailing room so the end-of-row add buttons (up to a
    /// dashed pill) are fully scrollable into view, never half-clipped.
    private var contentWidth: CGFloat { max(model.totalDuration, 0.1) * pps + 130 }

    private var contentHeight: CGFloat {
        lanes.laneContentHeight(
            overlayLanes: model.overlayLaneCount,
            musicLanes: model.musicLaneCount
        )
    }

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let halfWidth = VideoStudioMetrics.rowAreaHalfWidth(screenWidth: screenWidth, gutter: lanes.gutter)
            let visibleLeftTime = model.currentTime - Double(halfWidth / pps)

            VStack(spacing: 0) {
                // Inset by the gutter so the ruler's x = 0 lines up with the
                // scrolling content's x = 0.
                TimelineRuler(totalDuration: model.totalDuration, pps: pps, visibleLeftTime: visibleLeftTime)
                    .frame(height: lanes.ruler)
                    .padding(.leading, lanes.gutter)
                    .padding(.top, lanes.topPadding)
                    .padding(.bottom, lanes.rulerGap)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    VideoTimelineGutter(
                        overlayLaneCount: model.overlayLaneCount,
                        musicLaneCount: model.musicLaneCount,
                        activeLane: activeLane,
                        offsetY: laneOffsetY,
                        model: lanes.showsTrackControls ? model : nil
                    )
                    .zIndex(2)

                    VideoTimelineScroller(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        currentTime: model.currentTime,
                        pps: pps,
                        dragZones: dragZones,
                        onScrubStart: { model.beginScrub() },
                        onScrubTime: { scrub(to: $0) },
                        onScrubEnd: { model.endScrub(at: $0) },
                        onVerticalOffset: { laneOffsetY = $0 },
                        onPinch: handlePinch,
                        onZoneDrag: handleZoneDrag
                    ) {
                        TimelineTracksContent(
                            model: model,
                            pps: pps,
                            contentWidth: contentWidth,
                            visibleLeftTime: visibleLeftTime,
                            activeDrag: activeDrag,
                            onAddOverlay: onAddOverlay,
                            onAddMusic: onAddMusic,
                            onAddMedia: onAddMedia,
                            onEditText: onEditText,
                            onTransition: onTransition
                        )
                        .onPreferenceChange(TimelineDragZonesKey.self) { dragZones = $0 }
                    }
                    .background(alignment: .topLeading) { laneRails }
                    // The timeline holds still under a drag from Media: its
                    // pan is off for as long as a ghost is up.
                    .allowsHitTesting(model.mediaDrag == nil)
                }

                scrollbar(screenWidth: screenWidth)
                    .padding(.bottom, 2)
            }
            .overlay(alignment: .topLeading) {
                playhead.offset(x: VideoStudioMetrics.playheadX(screenWidth: screenWidth, gutter: lanes.gutter) - 1)
            }
            .overlay(alignment: .topLeading) { groupPill }
            .onAppear {
                if !hasAppliedWindowZoom {
                    hasAppliedWindowZoom = true
                    pps = zoomOverride ?? model.timelineZoom ?? lanes.pointsPerSecond
                    pinchStartPPS = pps
                }
                viewportWidth = screenWidth
                reportVisibleDuration(screenWidth: screenWidth)
            }
            .onChange(of: screenWidth) {
                viewportWidth = screenWidth
                reportVisibleDuration(screenWidth: screenWidth)
            }
            .onChange(of: pps) { reportVisibleDuration(screenWidth: screenWidth) }
            .onChange(of: zoomOverride) { _, new in
                pps = new ?? model.timelineZoom ?? lanes.pointsPerSecond
            }
            // Where a drag from Media can land (FS-12.09 §5), kept current
            // as the timeline moves, zooms, or stacks lanes.
            .onAppear { publishDropGeometry(geo) }
            .onChange(of: geo.frame(in: .global)) { publishDropGeometry(geo) }
            .onChange(of: pps) { publishDropGeometry(geo) }
            .onChange(of: laneOffsetY) { publishDropGeometry(geo) }
            .onChange(of: model.overlayLaneCount) { publishDropGeometry(geo) }
            .onDisappear { model.timelineDropGeometry = nil }
        }
        .frame(height: height)
        .background(EditorTheme.background)
        .clipped()
        // Still while an export runs (FS-12.10b §4).
        .allowsHitTesting(!model.isExportBusy)
        .onChange(of: model.fitToWindowToken) { fitToWindow() }
    }

    /// The lanes as a drop target: the whole lane area right of the gutter,
    /// the playhead's x, the zoom, and the video lane's band for the line.
    private func publishDropGeometry(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        let lanesTop = lanes.topPadding + lanes.ruler + lanes.rulerGap
        let videoTop = lanesTop
            + CGFloat(model.overlayLaneCount) * (lanes.overlay + lanes.laneGap)
            - laneOffsetY
        model.timelineDropGeometry = VideoDropGeometry(
            frame: CGRect(x: frame.minX + lanes.gutter, y: frame.minY, width: max(0, frame.width - lanes.gutter), height: frame.height),
            lineBand: CGRect(x: frame.minX, y: frame.minY + videoTop, width: frame.width, height: lanes.video),
            mapping: .timeline(
                playheadX: frame.minX + VideoStudioMetrics.playheadX(screenWidth: frame.width, gutter: lanes.gutter),
                pointsPerSecond: pps
            )
        )
    }

    private func reportVisibleDuration(screenWidth: CGFloat) {
        guard let onVisibleDuration, pps > 0 else { return }
        onVisibleDuration(Double(max(0, screenWidth - lanes.gutter) / pps))
    }

    /// An empty rail for every lane, the full width of the row.
    ///
    /// The playhead is parked at the centre and the project scrolls under it,
    /// so at t = 0 the leading half of the row has no clips in it. Drawn as
    /// bare background that read as a broken screen; drawn as track rails it
    /// reads as what it is — a timeline that has not started yet. CapCut's
    /// lanes run the whole width for the same reason.
    private var laneRails: some View {
        let overlays = max(1, model.overlayLaneCount)
        let musics = max(1, model.musicLaneCount)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<overlays, id: \.self) { lane in
                rail(height: lanes.overlay, top: lanes.overlayLaneTop(lane))
            }
            rail(height: lanes.video, top: lanes.videoLaneTop(overlayLanes: overlays))
            ForEach(0..<musics, id: \.self) { lane in
                rail(height: lanes.music, top: lanes.musicLaneTop(lane, overlayLanes: overlays))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(y: -laneOffsetY)
        .clipped()
        .allowsHitTesting(false)
    }

    private func rail(height: CGFloat, top: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
            .fill(EditorTheme.emptyLane)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: top)
    }

    /// The lane the selection sits in, so its gutter icon lights up.
    private var activeLane: VideoTimelineLane? {
        switch model.inspectorTarget {
        case .clip, .clips: .video
        case .text: model.selectedOverlayID.flatMap { model.overlayLaneAssignment[$0] }.map(VideoTimelineLane.overlay)
        case .music: model.selectedMusicID.flatMap { model.musicLaneAssignment[$0] }.map(VideoTimelineLane.music)
        case .none: nil
        }
    }

    // MARK: Multi-select pill (FS-12.11 §3)

    /// "✓ 3 selected 14.2s" at the head of the lanes while a group is
    /// open; out of the way while the group is being dragged.
    @ViewBuilder
    private var groupPill: some View {
        let isDragging: Bool = {
            guard let activeDrag, case .clipReorder = activeDrag.kind else { return false }
            return true
        }()
        if model.isSelectingClips, !isDragging {
            let summary = model.groupSummary
            let pill = VideoStudioMetrics.groupPill(desk: lanes.gutterStyle == .headers)
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                Text(VideoStudioCopy.selectedCount(summary.count))
                    .font(.system(size: 11, weight: .bold))
                Text(String(format: "%.1fs", summary.seconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .opacity(0.8)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .foregroundStyle(EditorTheme.timelineSelectionInk)
            .padding(.horizontal, 10)
            .frame(width: pill.size.width, height: pill.size.height)
            .background(Capsule().fill(EditorTheme.timelineSelection))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .offset(x: lanes.gutter + pill.inset, y: pill.top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("groupPill")
        }
    }

    // MARK: Playhead & scrollbar

    /// Runs the full height of the timeline: the lanes scroll under it, so it
    /// can't be sized to a fixed lane stack.
    private var playhead: some View {
        VStack(spacing: 0) {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 2, bottomLeading: 6, bottomTrailing: 6, topTrailing: 2),
                style: .continuous
            )
            .fill(.white)
            .frame(width: 11, height: 11)
            Rectangle()
                .fill(.white)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(
            height: height
                - lanes.topPadding
                - VideoStudioMetrics.scrollbarHeight
                - 2
        )
        .padding(.top, lanes.topPadding)
        .offset(x: -4.5)  // centre the 11pt cap on the 2pt line
        .allowsHitTesting(false)
    }

    private func scrollbar(screenWidth: CGFloat) -> some View {
        let rowWidth = screenWidth - lanes.gutter
        let width = max(20, rowWidth - 8)
        let total = max(model.totalDuration, 0.1)
        let viewportTime = Double(rowWidth / pps)
        let thumbFraction = min(1, viewportTime / total)
        let posFraction = total > 0 ? min(1 - thumbFraction, max(0, model.currentTime / total - thumbFraction / 2)) : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.07))
                .frame(width: width, height: VideoStudioMetrics.scrollbarHeight)
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(
                    width: max(20, width * CGFloat(thumbFraction)),
                    height: VideoStudioMetrics.scrollbarHeight
                )
                .offset(x: width * CGFloat(posFraction))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, lanes.gutter + 4)
        .allowsHitTesting(false)
    }

    // MARK: Scrub / pinch / fit

    private func scrub(to seconds: Double) {
        model.scrub(to: seconds)
        let second = Int(seconds)
        if second != lastHapticSecond {
            lastHapticSecond = second
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func handlePinch(_ phase: TimelinePinchPhase) {
        switch phase {
        case .began:
            pinchStartPPS = pps
        case .changed(let scale):
            pps = min(
                max(pinchStartPPS * scale, VideoStudioMetrics.pointsPerSecondRange.lowerBound),
                VideoStudioMetrics.pointsPerSecondRange.upperBound
            )
            // The user's zoom — not one the layout is imposing for now.
            if zoomOverride == nil { model.timelineZoom = pps }
        case .ended:
            break
        }
    }

    private func fitToWindow() {
        let rowWidth = viewportWidth - lanes.gutter
        guard model.totalDuration > 0.1, rowWidth > 0 else { return }
        let target = rowWidth / CGFloat(model.totalDuration)
        withAnimation(EditorTheme.animation) {
            pps = min(
                max(target, VideoStudioMetrics.pointsPerSecondRange.lowerBound),
                VideoStudioMetrics.pointsPerSecondRange.upperBound
            )
        }
        if zoomOverride == nil { model.timelineZoom = pps }
    }

    // MARK: Zone drag commit

    private func handleZoneDrag(_ kind: TimelineDragZone.Kind, _ phase: TimelineZoneDragPhase) {
        // An edge drag goes to the model at every phase: it previews the
        // frame at the edge while the finger moves, and a cancelled drag
        // has to reach it to put the playhead back.
        switch kind {
        case .clipLeadingHandle(let id), .clipTrailingHandle(let id):
            let edge: VideoEdgeTrimMath.Edge = if case .clipLeadingHandle = kind { .leading } else { .trailing }
            let snap = Double(8 / pps)
            let feedback: VideoStudioModel.EdgeTrimFeedback = switch phase {
            case .changed(let tx):
                model.edgeTrim(id, edge: edge, phase: .changed(Double(tx) / Double(pps)), snapTolerance: snap)
            case .ended(let tx):
                model.edgeTrim(id, edge: edge, phase: .ended(Double(tx) / Double(pps)), snapTolerance: snap)
            case .cancelled, .pressed, .holding, .modifiedTap:
                model.edgeTrim(id, edge: edge, phase: .cancelled)
            }
            // One tick when the edge reaches the source's end or a clip's
            // minimum, one when it sticks to a mark — not one per frame.
            if feedback.hitLimit, !edgeAtLimit { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            if feedback.snapped, !edgeSnapped { UISelectionFeedbackGenerator().selectionChanged() }
            edgeAtLimit = feedback.hitLimit
            edgeSnapped = feedback.snapped
            if case .changed = phase {} else { edgeAtLimit = false; edgeSnapped = false }
            return
        default:
            break
        }
        switch phase {
        case .holding(let x):
            pressStart.x = x
            if case .clipReorder(let id) = kind { model.clipPressGate.began(on: id) }
        case .modifiedTap(let command, let shift):
            model.clipPressGate.ended()
            if case .clipReorder(let id) = kind {
                if shift { model.shiftClickClip(id) } else if command { model.commandClickClip(id) }
            }
        case .changed(let tx):
            activeDrag = TimelineActiveDrag(kind: kind, translationX: tx, startX: pressStart.x)
        case .ended(let tx):
            model.clipPressGate.ended()
            commit(kind, translationX: tx)
            activeDrag = nil
        case .cancelled:
            model.clipPressGate.ended()
            activeDrag = nil
        case .pressed(let outcome):
            // Held in place and let go (FS-12.11 §4): half a second or more
            // selects the clip into a group; under that it is nothing at
            // all — no selection, no move, no step.
            model.clipPressGate.ended()
            activeDrag = nil
            if outcome == .enterSelection, case .clipReorder(let id) = kind {
                if !model.isSelectingClips {
                    model.enterClipSelection(id)
                } else if !model.selectedClipIDs.contains(id) {
                    model.toggleGroupClip(id)
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func commit(_ kind: TimelineDragZone.Kind, translationX: CGFloat) {
        let delta = Double(translationX) / Double(pps)
        // What "close enough to stick" means in seconds depends on the zoom:
        // 8pt of finger at any scale, so snapping feels the same whether the
        // timeline shows four seconds or forty.
        let snap = Double(8 / pps)
        switch kind {
        case .overlayBody(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let limit = max(0, model.totalDuration - base)
            model.pushUndo()
            let moved = model.snappedTime(timed.start + delta, within: snap)
            model.setOverlayTiming(start: min(max(0, moved), limit), duration: timed.duration, forOverlay: id)
        case .overlayLeadingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let end = timed.start + base
            let newStart = min(max(0, model.snappedTime(timed.start + delta, within: snap)), end - 0.5)
            model.pushUndo()
            model.setOverlayTiming(start: newStart, duration: end - newStart, forOverlay: id)
        case .overlayTrailingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let snappedEnd = model.snappedTime(timed.start + base + delta, within: snap)
            let newDuration = min(max(0.5, snappedEnd - timed.start), max(0.5, model.totalDuration - timed.start))
            model.pushUndo()
            model.setOverlayTiming(start: timed.start, duration: newDuration, forOverlay: id)
        case .clipFadeInHandle(let id):
            guard let clip = model.recipe.clips.first(where: { $0.id == id }) else { return }
            model.pushUndo()
            model.setFade(clip.fadeIn + delta, at: .start, for: id)
        case .clipFadeOutHandle(let id):
            guard let clip = model.recipe.clips.first(where: { $0.id == id }) else { return }
            model.pushUndo()
            // Dragging the trailing grip leftwards makes the fade longer, so
            // the sign flips — the grip moves with the finger, the value
            // moves against it.
            model.setFade(clip.fadeOut - delta, at: .end, for: id)
        case .musicBody(let id):
            guard let music = model.recipe.musicTracks.first(where: { $0.id == id }) else { return }
            model.pushUndo()
            model.setMusicStart(model.snappedTime(music.start + delta, within: snap), for: id)
        case .musicLeadingHandle(let id):
            // Head trim moves the source window and the placement together, in
            // one undo step, so the untouched tail stays where it plays.
            model.trimMusicHead(by: delta, for: id)
        case .musicTrailingHandle(let id):
            guard let music = model.recipe.musicTracks.first(where: { $0.id == id }),
                  let sourceDuration = music.sourceDuration
            else { return }
            let end = music.trimEnd ?? sourceDuration
            model.pushUndo()
            model.setMusicTrim(start: music.trimStart, end: end + delta, for: id)
        case .clipReorder(let id):
            guard let sourceIndex = model.recipe.clips.firstIndex(where: { $0.id == id }) else { return }
            let placements = model.clipPlacements
            guard sourceIndex < placements.count else { return }
            if model.selectedClipIDs.contains(id) {
                // A clip of the group carries the whole group (FS-12.11 §6):
                // it lands at the boundary the finger points at.
                let fingerTime = Double(pressStart.x + translationX) / Double(pps)
                let boundary = VideoClipGroupEditing.boundary(forFingerTime: fingerTime, placements: placements)
                model.moveClips(model.selectedClipIDs, toBoundary: boundary)
            } else {
                let widths = placements.map { max(16, Double($0.duration) * Double(pps)) }
                let boundary = VideoClipGroupEditing.singleMoveBoundary(
                    clipAt: sourceIndex, tileWidths: widths, translation: Double(translationX)
                )
                model.moveClips([id], toBoundary: boundary)
            }
        case .clipLeadingHandle, .clipTrailingHandle:
            break  // handled in `handleZoneDrag`, phase by phase
        }
    }
}

/// Where a press on a clip's body came down, in the timeline's content.
@MainActor
final class TimelinePressStart {
    var x: CGFloat = 0
}
