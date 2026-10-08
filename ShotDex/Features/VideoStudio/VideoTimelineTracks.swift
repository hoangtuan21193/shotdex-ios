import Photos
import SwiftUI
import ShotDexKit

/// A zone drag in flight: which zone, and how far the finger has moved. Rows
/// render their draft geometry from this; the commit happens on end.
struct TimelineActiveDrag: Equatable {
    var kind: TimelineDragZone.Kind
    var translationX: CGFloat
    /// Where in the content the finger came down — a group's drag follows
    /// the finger itself, not a clip's offset (FS-12.11 §6).
    var startX: CGFloat = 0
}

/// The drag zones the rows publish for the scroller's UIKit recognizers.
struct TimelineDragZonesKey: PreferenceKey {
    static let defaultValue: [TimelineDragZone] = []
    static func reduce(value: inout [TimelineDragZone], nextValue: () -> [TimelineDragZone]) {
        value.append(contentsOf: nextValue())
    }
}

/// The scrolling timeline content: overlay lanes above the video lane, music
/// lanes below it, every band positioned at `start * pps`. Lanes are assigned by
/// `TimelineLaneLayout`, so overlapping overlays (or music beds) stack instead of
/// drawing over each other, and the stack scrolls vertically when it outgrows
/// the viewport. The ruler is pinned by the parent and is not part of this
/// content. Selection is timeline-blue; the empty background clears it on tap.
struct TimelineTracksContent: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let contentWidth: CGFloat
    /// Timeline time at the visible left edge — drives sticky band labels.
    let visibleLeftTime: Double
    /// How wide the visible stretch of lanes is: with `visibleLeftTime`, the
    /// window a filmstrip draws its frames in (FS-12.17 §13).
    var visibleWidth: CGFloat = .infinity
    let activeDrag: TimelineActiveDrag?

    @Environment(\.videoLaneMetrics) private var lanes

    let onAddOverlay: () -> Void
    let onAddMusic: () -> Void
    let onAddMedia: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onTransition: (Int) -> Void

    private var placements: [VideoTimelineMath.Placement] { model.clipPlacements }

    var body: some View {
        let overlayLanes = model.overlayLaneAssignment
        let overlayLaneCount = model.overlayLaneCount
        let musicLanes = model.musicLaneAssignment
        let musicLaneCount = model.musicLaneCount

        VStack(spacing: lanes.laneGap) {
            if lanes.caption > 0 {
                VideoCaptionLaneRow(model: model, pps: pps, visibleLeftTime: visibleLeftTime, activeDrag: activeDrag)
                    .frame(width: contentWidth, height: lanes.caption, alignment: .leading)
            }
            ForEach(0..<overlayLaneCount, id: \.self) { lane in
                OverlayLaneRow(
                    model: model,
                    lane: lane,
                    laneAssignment: overlayLanes,
                    pps: pps,
                    visibleLeftTime: visibleLeftTime,
                    activeDrag: activeDrag,
                    onAdd: onAddOverlay
                )
                .frame(width: contentWidth, height: lanes.overlay, alignment: .leading)
            }

            VideoTrack(
                model: model,
                pps: pps,
                placements: placements,
                visibleWindow: CGFloat(visibleLeftTime) * pps...(CGFloat(visibleLeftTime) * pps + max(0, visibleWidth)),
                activeDrag: activeDrag,
                onAddMedia: onAddMedia,
                onTransition: onTransition
            )
            .frame(width: contentWidth, height: lanes.video, alignment: .leading)

            ForEach(0..<musicLaneCount, id: \.self) { lane in
                MusicLaneRow(
                    model: model,
                    lane: lane,
                    laneAssignment: musicLanes,
                    pps: pps,
                    visibleLeftTime: visibleLeftTime,
                    activeDrag: activeDrag,
                    onAdd: onAddMusic
                )
                .frame(width: contentWidth, height: lanes.music, alignment: .leading)
            }
        }
        .padding(.bottom, VideoStudioMetrics.timelineBottomPadding)
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.clearSelection() }
        .coordinateSpace(name: "timelineContent")
    }
}

// MARK: - Ruler

/// Second ticks (major every 1s with a label, minor every 0.5s). Drawn in
/// viewport space by the parent so it stays pinned while the lanes scroll
/// vertically; `visibleLeftTime` is the timeline time at x = 0.
struct TimelineRuler: View {
    let totalDuration: Double
    let pps: CGFloat
    let visibleLeftTime: Double
    /// The project's frame rate: at Frame zoom the ruler counts its frames
    /// (FS-12.17 §6).
    var fps: Int = 30

    var body: some View {
        Canvas { context, size in
            guard pps > 0 else { return }
            if TimelineZoomMath.isFrameZoom(pps, fps: fps) {
                drawFrames(in: &context, size: size)
                return
            }
            // The rule runs the whole width even where there is no time to
            // mark yet. Before this the lead-in at t = 0 was blank canvas, so
            // the timeline looked like it started half way across the screen
            // instead of scrolling under a playhead that is parked there.
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                },
                with: .color(EditorTheme.trackBorder),
                lineWidth: 1
            )
            let firstHalf = (visibleLeftTime * 2).rounded(.down) / 2
            var half = max(0, firstHalf)
            let last = min(totalDuration + 0.5, visibleLeftTime + Double(size.width / pps) + 0.5)
            while half <= last {
                let x = CGFloat(half - visibleLeftTime) * pps
                if x > size.width + 1 { break }
                if x >= -1 {
                    let isMajor = half.truncatingRemainder(dividingBy: 1) == 0
                    let tickHeight: CGFloat = isMajor ? 7 : 4
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        },
                        with: .color(.white.opacity(isMajor ? 0.36 : 0.22)),
                        lineWidth: 1
                    )
                    if isMajor {
                        let second = Int(half)
                        let atRightEdge = x > size.width - 20
                        context.draw(
                            Text("\(second)s")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.36)),
                            at: CGPoint(x: atRightEdge ? x - 3 : x + 3, y: size.height - 15),
                            anchor: atRightEdge ? .trailing : .leading
                        )
                    }
                }
                half += 0.5
            }
        }
    }

    /// Frame zoom: a tick a frame, a taller one labelled "8:12f" every six
    /// (72pt).
    private func drawFrames(in context: inout GraphicsContext, size: CGSize) {
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            },
            with: .color(EditorTheme.trackBorder),
            lineWidth: 1
        )
        let rate = Double(max(1, fps))
        let every = TimelineZoomMath.framesPerRulerLabel
        var frame = max(0, Int((visibleLeftTime * rate).rounded(.down)))
        let last = Int(((min(totalDuration, visibleLeftTime + Double(size.width / pps))) * rate).rounded(.up)) + 1
        while frame <= last {
            let x = CGFloat(Double(frame) / rate - visibleLeftTime) * pps
            if x > size.width + 1 { break }
            if x >= -1 {
                let isMajor = frame % every == 0
                let tickHeight: CGFloat = isMajor ? 7 : 4
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.white.opacity(isMajor ? 0.36 : 0.22)),
                    lineWidth: 1
                )
                if isMajor {
                    context.draw(
                        Text(verbatim: TimelineZoomMath.rulerFrameLabel(frame: frame, fps: fps))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.36)),
                        at: CGPoint(x: x, y: size.height - 15),
                        anchor: .center
                    )
                }
            }
            frame += 1
        }
    }
}

// MARK: - Video track

private struct VideoTrack: View {
    @Environment(\.videoLaneMetrics) private var lanes
    @Environment(\.videoStudioWindowClass) private var windowClass

    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let placements: [VideoTimelineMath.Placement]
    /// The lanes' visible stretch, in content points.
    var visibleWindow: ClosedRange<CGFloat>? = nil
    let activeDrag: TimelineActiveDrag?
    let onAddMedia: () -> Void
    let onTransition: (Int) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(model.recipe.clips.enumerated()), id: \.element.id) { index, clip in
                if index < placements.count {
                    ClipBand(
                        model: model, clip: clip, placement: placements[index], pps: pps,
                        reorderShift: reorderShift(clip),
                        isLiftedFrom: groupDrag != nil && model.selectedClipIDs.contains(clip.id),
                        visibleWindow: visibleWindow
                    )
                }
            }
            if model.mode == .multiClip {
                transitionChips
            }
            addMediaButton
            if let groupDrag {
                dropLine(at: groupDrag.boundary)
                groupStack(at: groupDrag.fingerX)
            } else if let preview = model.cutToBeatPreview {
                cutToBeatMarks(preview)
            }
            if showsVoiceLabels { voiceLabels }
            if groupDrag == nil, model.isPlacingGroup {
                // Move without a drag: the line follows the playhead, and
                // its pill is the button that drops (FS-12.11 §6).
                dropLine(at: model.placingBoundary, dropsOnTap: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(EditorTheme.animation, value: model.selectedClipID)
    }

    /// "Voice" on V1 over every stretch with someone speaking, on the
    /// iPad and the Duo's inner display, while a bed's Ducking tab is open
    /// (FS-12.13 §3) — 16pt tall, 14 on the Duo.
    private var showsVoiceLabels: Bool {
        // The phone has no room for C1 (FS-12.14 §3): a clip with spoken
        // captions wears a Voice chip where they are.
        if windowClass == .phone, model.hasCaptionLane, !model.placedCaptions.isEmpty { return true }
        guard model.activeItemCommand == .ducking, model.selectedMusicTrack != nil else { return false }
        switch windowClass {
        case .iPadLandscape, .iPadPortrait, .duoInner: return true
        default: return false
        }
    }

    /// Where the chips go: the ducking's voices while its tab is open, else
    /// the captions' stretches, a gap under 0.4 s closed.
    private var voiceSpans: [(start: Double, duration: Double)] {
        if model.activeItemCommand == .ducking, model.selectedMusicTrack != nil {
            return model.voiceSpansOnTimeline.map { ($0.start, $0.duration) }
        }
        var spans: [(start: Double, end: Double)] = []
        for placed in model.placedCaptions {
            if let last = spans.last, placed.start - last.end < CaptionChunker.pauseBreak {
                spans[spans.count - 1].end = max(last.end, placed.end)
            } else {
                spans.append((placed.start, placed.end))
            }
        }
        return spans.map { ($0.start, $0.end - $0.start) }
    }

    private var voiceLabels: some View {
        let height: CGFloat = windowClass == .duoInner ? 14 : 16
        return ZStack(alignment: .topLeading) {
            ForEach(Array(voiceSpans.enumerated()), id: \.offset) { _, voice in
                Text(VideoStudioCopy.voiceLabel)
                    .font(.system(size: height == 16 ? 10.5 : 9.5, weight: .semibold))
                    .foregroundStyle(EditorTheme.timelineSpeechInk)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(width: max(1, CGFloat(voice.duration) * pps), height: height, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous).fill(EditorTheme.timelineSpeech))
                    .clipped()
                    .offset(x: CGFloat(voice.start) * pps, y: lanes.video - height)
            }
        }
        .frame(height: lanes.video, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func reorderShift(_ clip: VideoClip) -> CGFloat {
        guard groupDrag == nil, let activeDrag, case .clipReorder(let id) = activeDrag.kind, id == clip.id
        else { return 0 }
        return activeDrag.translationX
    }

    /// A drag that started on a clip of the group (FS-12.11 §6): where the
    /// finger is, and the boundary it points at.
    private var groupDrag: (fingerX: CGFloat, boundary: Int)? {
        guard let activeDrag, case .clipReorder(let id) = activeDrag.kind,
              model.selectedClipIDs.contains(id), pps > 0
        else { return nil }
        let x = activeDrag.startX + activeDrag.translationX
        return (x, VideoClipGroupEditing.boundary(forFingerTime: Double(x / pps), placements: placements))
    }

    /// Cut to Beat's preview on the lane (FS-12.12 §6, board F2_DI): from
    /// each cut that moves, a 2pt arrow in the beat colour to its bar, a
    /// dashed 2×74 line at the bar, and the move in a 40×16 pill.
    private func cutToBeatMarks(_ preview: CutToBeatMath.Preview) -> some View {
        let moving = preview.cuts.filter(\.moves)
        let lineHeight: CGFloat = 74
        let top = (lanes.clipCell - lineHeight) / 2
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for cut in moving {
                    guard let target = cut.target else { continue }
                    let from = CGFloat(cut.time) * pps
                    let to = CGFloat(target) * pps
                    let y = lanes.clipCell / 2
                    var shaft = Path()
                    shaft.move(to: CGPoint(x: from, y: y))
                    shaft.addLine(to: CGPoint(x: to, y: y))
                    context.stroke(shaft, with: .color(EditorTheme.timelineBeat), lineWidth: 2)
                    let direction: CGFloat = to >= from ? 1 : -1
                    var head = Path()
                    head.move(to: CGPoint(x: to, y: y))
                    head.addLine(to: CGPoint(x: to - 6 * direction, y: y - 4))
                    head.addLine(to: CGPoint(x: to - 6 * direction, y: y + 4))
                    head.closeSubpath()
                    context.fill(head, with: .color(EditorTheme.timelineBeat))
                    var line = Path()
                    line.move(to: CGPoint(x: to, y: top))
                    line.addLine(to: CGPoint(x: to, y: top + lineHeight))
                    context.stroke(line, with: .color(EditorTheme.timelineBeat), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .frame(width: CGFloat(model.totalDuration) * pps + 40, height: lanes.clipCell)
            ForEach(moving, id: \.clipIndex) { cut in
                Text(VideoStudioCopy.cutShift(cut.shift))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(EditorTheme.timelineBeatInk)
                    .frame(width: VideoStudioMetrics.cutToBeatPill.width, height: VideoStudioMetrics.cutToBeatPill.height)
                    .background(Capsule().fill(EditorTheme.timelineBeat))
                    .offset(
                        x: CGFloat(cut.target ?? cut.time) * pps - VideoStudioMetrics.cutToBeatPill.width / 2,
                        y: top - VideoStudioMetrics.cutToBeatPill.height - 2
                    )
            }
        }
        .allowsHitTesting(false)
        .zIndex(4)
        .accessibilityHidden(true)
    }

    /// The drop line, 3×82 in the selection colour with a glow, and over it
    /// "Move 2 clips here" (100×18).
    private func dropLine(at boundary: Int, dropsOnTap: Bool = false) -> some View {
        let x = CGFloat(VideoClipGroupEditing.boundaryTime(boundary, placements: placements)) * pps
        let size = VideoStudioMetrics.groupDropLine
        let top = (lanes.clipCell - size.height) / 2
        let pill = Text(VideoStudioCopy.moveClipsHere(model.selectedClipIDs.count))
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(EditorTheme.timelineSelectionInk)
            .padding(.horizontal, 6)
            .frame(width: VideoStudioMetrics.groupDropPill.width, height: VideoStudioMetrics.groupDropPill.height)
            .background(Capsule().fill(EditorTheme.timelineSelection))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(EditorTheme.timelineSelection)
                .frame(width: size.width, height: size.height)
                .shadow(color: EditorTheme.timelineSelection.opacity(0.8), radius: 6)
                .offset(x: x - size.width / 2, y: top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Group {
                if dropsOnTap {
                    Button { model.placeGroupAtLine() } label: {
                        // The pill answers a 44pt-tall touch, drawn 18 tall.
                        pill.frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Scroll the timeline to move the line", tableName: VideoStudioCopy.table, comment: "Video Studio multi-select: VoiceOver hint on the Move pill — the line follows the playhead as the timeline scrolls"))
                    .offset(y: -13)
                } else {
                    pill
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .offset(x: x - VideoStudioMetrics.groupDropPill.width / 2, y: top - VideoStudioMetrics.groupDropPill.height - 2)
        }
        .zIndex(4)
    }

    /// The group lifted under the finger: a 131×54 stack — the first clip
    /// 80 wide, the next ones 50 — with a 2pt ring and the count in a 22pt
    /// badge.
    private func groupStack(at fingerX: CGFloat) -> some View {
        let clips = model.recipe.clips.filter { model.selectedClipIDs.contains($0.id) }
        let size = VideoStudioMetrics.groupStack
        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 1) {
                ForEach(Array(clips.prefix(2).enumerated()), id: \.element.id) { index, clip in
                    ClipFilmstrip(
                        assetID: clip.assetID,
                        fileURL: model.serverFileURL(for: clip.assetID),
                        photoLibrary: model.photoLibrary,
                        width: index == 0 ? 80 : size.width - 81,
                        height: size.height
                    )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .strokeBorder(EditorTheme.timelineSelection, lineWidth: VideoStudioMetrics.groupRing)
            }
            Text("\(clips.count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(EditorTheme.timelineSelectionInk)
                .frame(width: VideoStudioMetrics.groupCountBadge, height: VideoStudioMetrics.groupCountBadge)
                .background(Circle().fill(EditorTheme.timelineSelection))
                .offset(x: 8, y: -8)
        }
        .shadow(color: .black.opacity(0.5), radius: 8)
        .offset(x: fingerX - size.width / 2, y: (lanes.clipCell - size.height) / 2)
        .allowsHitTesting(false)
        .zIndex(5)
        .accessibilityHidden(true)
    }

    private var addMediaButton: some View {
        let end = (placements.last?.end ?? 0)
        return Button(action: onAddMedia) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: VideoStudioMetrics.addMediaButtonWidth, height: lanes.clipCell)
                .background(
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .fill(EditorTheme.trackBorder)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add photo or video")
        .offset(x: CGFloat(end) * pps + 8)
    }

    private var transitionChips: some View {
        ForEach(0..<max(0, min(model.recipe.transitions.count, placements.count - 1)), id: \.self) { index in
            let transition = model.recipe.transitions[index]
            let x = CGFloat((placements[index].end + placements[index + 1].start) / 2) * pps
            Button { onTransition(index) } label: {
                Image(systemName: transition.kind == .none ? "bowtie" : transitionGlyph(transition.kind))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: VideoStudioMetrics.transitionChipSize, height: VideoStudioMetrics.transitionChipSize)
                    .background(
                        RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
                    .overlay {
                        if transition.kind != .none {
                            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                                .strokeBorder(EditorTheme.accent, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transition")
            .offset(
                x: x - VideoStudioMetrics.transitionChipSize / 2,
                y: (lanes.clipCell - VideoStudioMetrics.transitionChipSize) / 2
            )
            .zIndex(2)
        }
    }

    private func transitionGlyph(_ kind: VideoTransitionKind) -> String {
        switch kind {
        case .none: "bowtie"
        case .crossfade: "square.filled.on.square"
        case .fadeBlack: "moon.fill"
        case .slideLeft: "arrow.left.square"
        case .slideRight: "arrow.right.square"
        case .wipe: "rectangle.lefthalf.filled"
        case .zoom: "plus.magnifyingglass"
        }
    }
}

/// One video / photo / freeze cell: a filmstrip thumbnail, duration badge, and
/// (for the selected clip) a 2.5px timeline-blue border. Reorder rides a
/// long-press; the draft shift comes from `reorderShift`.
private struct ClipBand: View {
    @Environment(\.videoLaneMetrics) private var lanes

    @Bindable var model: VideoStudioModel
    let clip: VideoClip
    let placement: VideoTimelineMath.Placement
    let pps: CGFloat
    let reorderShift: CGFloat
    /// Where a lifted group came from (FS-12.11 §6): darkened 0.66 under a
    /// dashed 1.5pt ring while the group is in the air.
    var isLiftedFrom = false
    /// The lanes' visible stretch, in content points: the filmstrip draws
    /// only the frames that fall in it.
    var visibleWindow: ClosedRange<CGFloat>? = nil

    private var isSelected: Bool { model.selectedClipID == clip.id }
    /// In the multi-select group (FS-12.11 §3): a 2pt ring and a ✓ badge,
    /// no edge handles or fade grips — those edit one clip.
    private var isInGroup: Bool { model.selectedClipIDs.contains(clip.id) }
    private var width: CGFloat { max(16, CGFloat(placement.duration) * pps) }

    var body: some View {
        ClipFilmstrip(
            assetID: clip.assetID,
            fileURL: model.serverFileURL(for: clip.assetID),
            photoLibrary: model.photoLibrary,
            width: width,
            height: lanes.clipCell,
            visibleRange: visibleWindow.map { window in
                let left = CGFloat(placement.start) * pps + reorderShift
                return (window.lowerBound - left)...(window.upperBound - left)
            }
        )
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay(alignment: .bottomLeading) { corners }
        .overlay(alignment: .topLeading) { lookPill }
        .clipShape(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .strokeBorder(
                    isSelected || isInGroup ? EditorTheme.timelineSelection : EditorTheme.trackBorder,
                    lineWidth: isSelected ? 2.5 : (isInGroup ? VideoStudioMetrics.groupRing : 1)
                )
        }
        .overlay(alignment: .topTrailing) { groupBadge }
        .overlay {
            if isLiftedFrom {
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .fill(Color.black.opacity(0.66))
                    .overlay {
                        RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                            .strokeBorder(EditorTheme.timelineSelection, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
            }
        }
        .frame(width: width, height: lanes.clipCell)
        // Everything that is hit-tested goes on the clip's own frame,
        // *before* it is moved into place: a modifier added after `.offset`
        // sits on the unmoved frame at the lane's origin, where every clip's
        // frame is — so a tap on the first clip went to the topmost one, and
        // the selected clip's fade knobs drew over clip 1.
        .contentShape(Rectangle())
        .onTapGesture {
            // The tail of a held press is the press's (FS-12.11 §4).
            guard !model.clipPressGate.swallowsTap(on: clip.id) else { return }
            model.toggleClip(clip.id)
        }
        // The clip is one element; its edge handles are two more, beside
        // it — adjustable a frame at a time (FS-12.17 §5, AC-14).
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected || isInGroup ? [.isSelected, .isButton] : .isButton)
        .background(reorderZone)
        .overlay(edgeHandles)
        .overlay(fadeZones)
        .offset(x: CGFloat(placement.start) * pps + reorderShift)
        .scaleEffect(reorderShift != 0 ? 1.05 : 1)
        .zIndex(reorderShift != 0 ? 3 : 0)
        .shadow(color: reorderShift != 0 ? .black.opacity(0.5) : .clear, radius: 8)
    }

    /// The ✓ of a clip in the group: a 19pt disc in the selection colour,
    /// a dark tick, 5 in from the top and trailing edges.
    @ViewBuilder
    private var groupBadge: some View {
        if isInGroup {
            Circle()
                .fill(EditorTheme.timelineSelection)
                .frame(width: VideoStudioMetrics.groupBadge, height: VideoStudioMetrics.groupBadge)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(EditorTheme.timelineSelectionInk)
                }
                .padding(VideoStudioMetrics.groupBadgeInset)
                .accessibilityHidden(true)
        }
    }

    private var durationBadge: some View {
        Text("\(clip.effectiveDuration.formatted(.number.precision(.fractionLength(1))))s")
            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .padding(3)
    }

    /// The clip's own look, by name (FS-12.06c §3): only a clip with a
    /// look of its own wears one; a clip following the whole video's look
    /// has nothing to say here.
    @ViewBuilder
    private var lookPill: some View {
        if let name = model.lookPillText(for: clip) {
            HStack(spacing: 4) {
                Image(systemName: VideoItemCommand.look.systemImage)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(verbatim: name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: VideoStudioMetrics.lookPillHeight)
            .background(Capsule().fill(Color.black.opacity(0.66)))
            .padding(3)
            // Clear of the fade grip a selected clip wears at its corner.
            .padding(.leading, isSelected ? 18 : 0)
            .accessibilityHidden(true)
        }
    }

    private var corners: some View {
        HStack(spacing: 3) {
            if clip.kind == .video, clip.isMuted {
                Image(systemName: "speaker.slash.fill").font(.system(size: 8.5))
            }
            if clip.kind == .video, clip.speed != 1 {
                Text("\(clip.speed.formatted(.number.precision(.significantDigits(2))))×").font(.system(size: 8, weight: .bold).monospacedDigit())
            }
            if clip.kind == .freeze {
                Image(systemName: "snowflake").font(.system(size: 8.5))
            }
        }
        .foregroundStyle(.white)
        .padding(3)
    }

    /// Built from localized parts, not from English literals interpolated
    /// into a `String`: this is the only way a blind user reads the timeline,
    /// and a verbatim `String` would have stayed English in every language.
    private var accessibilityLabel: String {
        let kind = switch clip.kind {
        case .video: String(localized: "Video", comment: "Kind of timeline clip, read by VoiceOver")
        case .freeze: String(localized: "Freeze", comment: "Kind of timeline clip — a frozen frame — read by VoiceOver")
        default: String(localized: "Photo", comment: "Kind of timeline clip, read by VoiceOver")
        }
        let label = String(
            localized: "\(kind) clip, from second \(Int(placement.start)) to \(Int(placement.end))",
            comment: "VoiceOver label for one clip on the Video Studio timeline: its kind and the seconds it spans"
        )
        guard let look = model.lookPillText(for: clip) else { return label }
        return label + ", " + VideoStudioCopy.lookNamed(look)
    }

    /// The fade grips, and the wedge that shows how long the fade is.
    ///
    /// Drawn only on a selected clip: a grip on every clip in a forty-clip
    /// timeline is forty targets nobody aimed at, and the wedge would read as
    /// decoration rather than as a value.
    @ViewBuilder
    private var fadeZones: some View {
        if isSelected {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let seconds = max(placement.duration, 0.0001)
                let inWidth = CGFloat(clip.fadeIn / seconds) * width
                let outWidth = CGFloat(clip.fadeOut / seconds) * width
                ZStack(alignment: .topLeading) {
                    if inWidth > 1 { fadeWedge(width: inWidth, height: height, leading: true) }
                    if outWidth > 1 {
                        fadeWedge(width: outWidth, height: height, leading: false)
                            .offset(x: width - outWidth)
                    }
                    grip(leading: true).offset(x: max(0, inWidth - 11))
                    grip(leading: false).offset(x: min(width - 22, width - outWidth))
                }
                .allowsHitTesting(false)
                .preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(
                            kind: .clipFadeInHandle(clip.id),
                            rect: CGRect(
                                x: proxy.frame(in: .named("timelineContent")).minX + max(0, inWidth - 11),
                                y: proxy.frame(in: .named("timelineContent")).minY,
                                width: 22,
                                height: height
                            )
                        ),
                        TimelineDragZone(
                            kind: .clipFadeOutHandle(clip.id),
                            rect: CGRect(
                                x: proxy.frame(in: .named("timelineContent")).minX + min(width - 22, width - outWidth),
                                y: proxy.frame(in: .named("timelineContent")).minY,
                                width: 22,
                                height: height
                            )
                        ),
                    ]
                )
            }
        }
    }

    private var edgePreview: VideoStudioModel.EdgeTrimPreview? {
        guard let preview = model.edgeTrimPreview, preview.clipID == clip.id else { return nil }
        return preview
    }

    /// The frame trim open on this clip (FS-12.17 §3).
    private var frameTrim: FrameTrimSession? {
        guard let trim = model.frameTrim, trim.clipID == clip.id else { return nil }
        return trim
    }

    /// How far each edge sits from where it was, in points, while the
    /// frame trim is open: the edges are virtual until ✓.
    private func frameTrimOffsets(_ trim: FrameTrimSession) -> (lead: CGFloat, trail: CGFloat) {
        (
            CGFloat(trim.edgeTime(of: .leading) - trim.originTime(of: .leading)) * pps,
            CGFloat(trim.edgeTime(of: .trailing) - trim.originTime(of: .trailing)) * pps
        )
    }

    /// What the trim cuts off is hatched where it lies; what it adds is
    /// outlined in the selection colour over the next clip — the recipe has
    /// not changed yet and the next clip only closes up at ✓ (§3).
    @ViewBuilder
    private func frameTrimMarks(_ trim: FrameTrimSession, width: CGFloat, height: CGFloat) -> some View {
        let offsets = frameTrimOffsets(trim)
        ZStack(alignment: .topLeading) {
            if offsets.lead > 0.5 {
                FrameTrimHatch().frame(width: offsets.lead, height: height)
            } else if offsets.lead < -0.5 {
                FrameTrimAddedOutline().frame(width: -offsets.lead, height: height).offset(x: offsets.lead)
            }
            if offsets.trail < -0.5 {
                FrameTrimHatch().frame(width: -offsets.trail, height: height).offset(x: width + offsets.trail)
            } else if offsets.trail > 0.5 {
                FrameTrimAddedOutline().frame(width: offsets.trail, height: height).offset(x: width)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The edge handles (FS-12.05 §3): a 12pt tab in the selection colour
    /// outside each edge of the selected clip, the clip's height; each
    /// answers a 44pt-wide drag (16 of it outside the clip). The top 20pt is
    /// the fade grips', so a drag that starts on a grip sets the fade.
    @ViewBuilder
    private var edgeHandles: some View {
        if isSelected {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let frame = proxy.frame(in: .named("timelineContent"))
                let preview = edgePreview
                let trimOffsets = frameTrim.map(frameTrimOffsets)
                let lead = trimOffsets?.lead ?? (preview?.edge == .leading ? CGFloat(preview?.appliedDelta ?? 0) * pps : 0)
                let trail = trimOffsets?.trail ?? (preview?.edge == .trailing ? CGFloat(preview?.appliedDelta ?? 0) * pps : 0)
                let band = VideoStudioMetrics.edgeHandleTouchWidth
                let outside = VideoStudioMetrics.edgeHandleTouchOutside
                let fadeBand = VideoStudioMetrics.fadeGripBand
                ZStack(alignment: .topLeading) {
                    if let frameTrim { frameTrimMarks(frameTrim, width: width, height: height) }
                    edgeTab(leading: true)
                        .accessibilityElement()
                        .modifier(EdgeHandleAccessibility(model: model, clip: clip, edge: .leading))
                        .offset(x: -VideoStudioMetrics.edgeHandleWidth + lead)
                    edgeTab(leading: false)
                        .accessibilityElement()
                        .modifier(EdgeHandleAccessibility(model: model, clip: clip, edge: .trailing))
                        .offset(x: width + trail)
                    if let preview {
                        Text("\(preview.result.duration.formatted(.number.precision(.fractionLength(1))))s")
                            .accessibilityHidden(true)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Capsule().fill(EditorTheme.timelineSelection))
                            .offset(x: preview.edge == .leading ? lead + 4 : width + trail - 40, y: -18)
                    }
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .allowsHitTesting(false)
                .preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        // The zones follow a trimmed edge, so the finger finds
                        // the handle where it is drawn.
                        TimelineDragZone(
                            kind: .clipLeadingHandle(clip.id),
                            rect: CGRect(x: frame.minX - outside + (trimOffsets?.lead ?? 0), y: frame.minY + fadeBand, width: band, height: max(0, height - fadeBand))
                        ),
                        TimelineDragZone(
                            kind: .clipTrailingHandle(clip.id),
                            rect: CGRect(x: frame.maxX + outside - band + (trimOffsets?.trail ?? 0), y: frame.minY + fadeBand, width: band, height: max(0, height - fadeBand))
                        ),
                    ]
                )
            }
        }
    }

    private func edgeTab(leading: Bool) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: leading
                ? .init(topLeading: 4, bottomLeading: 4)
                : .init(bottomTrailing: 4, topTrailing: 4),
            style: .continuous
        )
        .fill(EditorTheme.timelineSelection)
        .frame(width: VideoStudioMetrics.edgeHandleWidth, height: lanes.clipCell)
        .overlay {
            Capsule().fill(Color.black.opacity(0.5)).frame(width: 2, height: 14)
        }
    }

    private func fadeWedge(width: CGFloat, height: CGFloat, leading: Bool) -> some View {
        Path { path in
            if leading {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
            } else {
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            path.closeSubpath()
        }
        .fill(Color.black.opacity(0.55))
        .frame(width: width, height: height)
    }

    private func grip(leading: Bool) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
            .padding(.top, 3)
            .padding(leading ? .leading : .trailing, 3)
    }

    /// Every clip's body takes the press (FS-12.11 §4) — selected or not:
    /// held then dragged it moves, held and let go it selects. A locked
    /// lane lifts nothing (§8).
    @ViewBuilder
    private var reorderZone: some View {
        if model.mode == .multiClip, !model.isLaneLocked(.video) {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [TimelineDragZone(
                        kind: .clipReorder(clip.id),
                        rect: proxy.frame(in: .named("timelineContent"))
                    )]
                )
            }
        }
    }
}

/// A clip's edge handle for VoiceOver (FS-12.17 AC-14): "Clip 2 end",
/// its time "0:09.20"; swipe down moves it a frame earlier, up a frame
/// later — each one undo step, written at once.
private struct EdgeHandleAccessibility: ViewModifier {
    let model: VideoStudioModel
    let clip: VideoClip
    let edge: VideoEdgeTrimMath.Edge

    func body(content: Content) -> some View {
        let index = model.recipe.clips.firstIndex { $0.id == clip.id } ?? 0
        let name = VideoItemTitle.clip(clip, index: index).name
        content
            .accessibilityLabel(Text(verbatim: VideoStudioCopy.edgeHandleName(name, trailing: edge == .trailing)))
            .accessibilityValue(Text(verbatim: model.clipEdgeTime(clip.id, edge: edge).map(VideoFrameGrid.hundredths) ?? ""))
            .accessibilityAdjustableAction { direction in
                model.stepClipEdge(clip.id, edge: edge, by: direction == .increment ? 1 : -1)
            }
            .accessibilityIdentifier(edge == .trailing ? "clipEndHandle" : "clipStartHandle")
    }
}

/// The part of a clip the frame trim cuts away: black 45 % under white
/// diagonal stripes 30 % (FS-12.17 §3).
private struct FrameTrimHatch: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.45)))
            var stripes = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(stripes, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }
    }
}

/// The time the frame trim adds past the clip's old edge, drawn over the
/// clip next to it: a 2pt selection-colour outline over a light wash.
private struct FrameTrimAddedOutline: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(EditorTheme.timelineSelection.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(EditorTheme.timelineSelection, lineWidth: 2)
            )
    }
}

/// A clip cell's filmstrip: one shared local thumbnail repeated so long clips
/// read as a strip without extra image requests.
struct ClipFilmstrip: View {
    let assetID: String
    /// A server copy on disk (FS-17.06 §5b), read instead of PhotoKit.
    var fileURL: URL?
    let photoLibrary: PhotoLibraryService
    let width: CGFloat
    let height: CGFloat
    /// The part of the strip on screen, in its own points. Only the frames
    /// that touch it (and one either side) are built: at Frame zoom a
    /// minute of clip is 21 600pt wide — hundreds of frames nobody sees
    /// (FS-12.17 §13). Nil builds them all.
    var visibleRange: ClosedRange<CGFloat>? = nil

    @State private var image: UIImage?

    var body: some View {
        let side = max(height, 1)
        let count = max(1, Int((width / side).rounded(.up)))
        let range = ClipFilmstrip.drawnCells(count: count, side: side, visible: visibleRange)
        ZStack(alignment: .topLeading) {
            if let range {
                ForEach(range, id: \.self) { index in
                    Rectangle()
                        .fill(EditorTheme.control)
                        .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                        .frame(width: height, height: height)
                        .clipped()
                        .offset(x: CGFloat(index) * side)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .onAppear {
            guard image == nil else { return }
            if let fileURL {
                let side = Int(max(240, height * ActiveDisplay.scale))
                Task { image = await PhotoOriginFile.loadImage(at: fileURL, maxPixelSize: side) }
                return
            }
            guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first
            else { return }
            // Sized from the cell the frame lands in, not a constant: an
            // 88pt regular-width cell on a 3x screen wants 264px, and a 240px
            // thumbnail upscaled into it is the soft filmstrip the taller
            // lanes were supposed to fix.
            let side = max(240, height * ActiveDisplay.scale)
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                allowNetwork: false
            ) { result in if let result { image = result } }
        }
    }

    /// The cells to build for a strip of `count` square cells `side` wide,
    /// of which `visible` is on screen: the ones it touches and one more
    /// each side. Nil when none is on screen.
    static func drawnCells(count: Int, side: CGFloat, visible: ClosedRange<CGFloat>?) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        guard let visible else { return 0...(count - 1) }
        let first = max(0, Int((visible.lowerBound / side).rounded(.down)) - 1)
        let last = min(count - 1, Int((visible.upperBound / side).rounded(.down)) + 1)
        return first <= last ? first...last : nil
    }
}

// MARK: - Overlay lanes

/// One lane of timed overlays — text and stickers share the same lane stack, so
/// a sticker's window is editable on the timeline just like a text bar's. Drag
/// the body to move, a handle to resize; the drags arrive from the scroller's
/// zone pan via `activeDrag`.
private struct OverlayLaneRow: View {
    @Bindable var model: VideoStudioModel
    let lane: Int
    let laneAssignment: [UUID: Int]
    let pps: CGFloat
    let visibleLeftTime: Double
    let activeDrag: TimelineActiveDrag?
    let onAdd: () -> Void

    private static let minimumDuration = 0.5

    private var overlaysInLane: [TimedOverlay] {
        model.recipe.overlays.filter { laneAssignment[$0.id] == lane }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(overlaysInLane) { timed in
                bar(timed)
            }
            if lane == 0, model.recipe.overlays.isEmpty {
                dashedAdd(title: "Text", systemImage: "textformat", action: onAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func window(_ timed: TimedOverlay) -> (start: Double, duration: Double) {
        let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
        guard let activeDrag else { return (timed.start, base) }
        let delta = Double(activeDrag.translationX) / Double(pps)
        switch activeDrag.kind {
        case .overlayBody(let id) where id == timed.id:
            let limit = max(0, model.totalDuration - base)
            return (min(max(0, timed.start + delta), limit), base)
        case .overlayLeadingHandle(let id) where id == timed.id:
            let end = timed.start + base
            let newStart = min(max(0, timed.start + delta), end - Self.minimumDuration)
            return (newStart, end - newStart)
        case .overlayTrailingHandle(let id) where id == timed.id:
            let duration = min(
                max(Self.minimumDuration, base + delta),
                max(Self.minimumDuration, model.totalDuration - timed.start)
            )
            return (timed.start, duration)
        default:
            return (timed.start, base)
        }
    }

    private func label(_ timed: TimedOverlay) -> (icon: String, title: String) {
        if timed.overlay.kind == .image {
            return ("photo", String(localized: "Sticker"))
        }
        return ("textformat", timed.overlay.text.isEmpty ? String(localized: "Text") : timed.overlay.text)
    }

    @ViewBuilder
    private func bar(_ timed: TimedOverlay) -> some View {
        let isSelected = model.selectedOverlayID == timed.id
        let win = window(timed)
        let width = max(28, CGFloat(win.duration) * pps)
        let stickyInset = min(max(0, CGFloat(visibleLeftTime - win.start) * pps), width - 40)
        let content = label(timed)

        chipBody(
            icon: content.icon,
            title: content.title,
            width: width,
            isSelected: isSelected,
            stickyInset: max(0, stickyInset)
        )
        .overlay(alignment: .leading) { if isSelected { handle } }
        .overlay(alignment: .trailing) { if isSelected { handle } }
        .contentShape(Rectangle().inset(by: VideoStudioMetrics.bandHitInset))
        .onTapGesture { model.toggleOverlay(timed.id) }
        .background(dragZones(timed, isSelected: isSelected))
        .offset(x: CGFloat(win.start) * pps)
        .accessibilityLabel("\(content.title), from second \(Int(win.start)) to \(Int(win.start + win.duration))")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(EditorTheme.timelineSelection)
            .frame(width: 4, height: VideoStudioMetrics.chipBandHeight - 6)
    }

    @ViewBuilder
    private func dragZones(_ timed: TimedOverlay, isSelected: Bool) -> some View {
        if isSelected {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("timelineContent")).insetBy(dx: 0, dy: -3)
                let handleWidth: CGFloat = 22
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(kind: .overlayLeadingHandle(timed.id), rect: CGRect(x: frame.minX - 14, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .overlayTrailingHandle(timed.id), rect: CGRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .overlayBody(timed.id), rect: frame.insetBy(dx: handleWidth, dy: 0)),
                    ]
                )
            }
        }
    }

    private func chipBody(icon: String, title: String, width: CGFloat, isSelected: Bool, stickyInset: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .fill(isSelected ? EditorTheme.timelineSelection.opacity(0.22) : Color.white.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .strokeBorder(isSelected ? EditorTheme.timelineSelection : Color.white.opacity(0.14), lineWidth: isSelected ? 1.5 : 1)
                }
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color(red: 0.804, green: 0.937, blue: 0.965) : .white)
            .padding(.leading, 6 + stickyInset)
            .padding(.trailing, 6)
        }
        .frame(width: width, height: VideoStudioMetrics.chipBandHeight)
    }
}

// MARK: - Music lanes

/// One lane of music beds. Each bar can be dragged along the timeline and
/// trimmed from either end; the waveform is windowed to the bed's trim so what
/// you see is what plays.
private struct MusicLaneRow: View {
    @Bindable var model: VideoStudioModel
    let lane: Int
    let laneAssignment: [UUID: Int]
    let pps: CGFloat
    let visibleLeftTime: Double
    let activeDrag: TimelineActiveDrag?
    let onAdd: () -> Void

    private var tracksInLane: [MusicTrack] {
        model.recipe.musicTracks.filter { laneAssignment[$0.id] == lane }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(tracksInLane) { music in
                bar(music)
            }
            if lane == 0, model.recipe.musicTracks.isEmpty {
                dashedAdd(title: "Music", systemImage: "music.note", action: onAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Draft geometry while a drag is in flight, mirroring what the commit will
    /// apply once the finger lifts.
    private func window(_ music: MusicTrack) -> (start: Double, duration: Double, trimStart: Double, trimEnd: Double) {
        let sourceDuration = music.sourceDuration ?? music.effectiveDuration
        let trimEnd = music.trimEnd ?? sourceDuration
        var start = music.start
        var trimStart = music.trimStart
        var end = trimEnd
        if let activeDrag {
            let delta = Double(activeDrag.translationX) / Double(pps)
            switch activeDrag.kind {
            case .musicBody(let id) where id == music.id:
                start = max(0, min(music.start + delta, max(0, model.totalDuration - MusicTrack.minimumDuration)))
            case .musicLeadingHandle(let id) where id == music.id:
                let lowerBound = max(-music.trimStart, -music.start)
                let upperBound = trimEnd - music.trimStart - MusicTrack.minimumDuration
                if upperBound >= lowerBound {
                    let applied = min(max(delta, lowerBound), upperBound)
                    trimStart = music.trimStart + applied
                    start = music.start + applied
                }
            case .musicTrailingHandle(let id) where id == music.id:
                end = min(max(trimEnd + delta, trimStart + MusicTrack.minimumDuration), sourceDuration)
            default:
                break
            }
        }
        return (start, max(MusicTrack.minimumDuration, end - trimStart), trimStart, end)
    }

    @ViewBuilder
    private func bar(_ music: MusicTrack) -> some View {
        let isSelected = model.selectedMusicID == music.id
        let win = window(music)
        let width = max(40, CGFloat(win.duration) * pps)
        let stickyInset = min(max(0, CGFloat(visibleLeftTime - win.start) * pps), width - 60)
        let sourceDuration = music.sourceDuration ?? win.duration

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .fill(isSelected ? EditorTheme.timelineSelection.opacity(0.22) : Color.white.opacity(0.06))
            WaveformShape(
                samples: model.musicWaveforms[music.id] ?? [],
                startFraction: sourceDuration > 0 ? win.trimStart / sourceDuration : 0,
                endFraction: sourceDuration > 0 ? win.trimEnd / sourceDuration : 1
            )
            .fill(isSelected ? EditorTheme.timelineSelection : Color.white.opacity(0.42))
            HStack(spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 9, weight: .bold))
                Text(music.displayName).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.leading, 5 + max(0, stickyInset))
        }
        .frame(width: width, height: VideoStudioMetrics.musicBandHeight)
        .overlay(alignment: .topLeading) {
            // The bed's beats while its Beats tab is open (FS-12.12 §3).
            if model.showsBeatTicks(for: music), let grid = model.beatGrid(for: music) {
                BeatTickMarks(ticks: grid.visibleTicks(pointsPerSecond: Double(pps)), origin: win.start, scale: Double(pps))
                    .frame(width: width, height: VideoStudioMetrics.musicBandHeight)
            }
        }
        .overlay(alignment: .topLeading) {
            // The bed's level while it ducks; the dB pills while its
            // Ducking tab is open (FS-12.13 §3).
            if music.ducking.isOn {
                DuckingLaneLine(
                    music: music,
                    dips: model.duckingDips(for: music),
                    origin: win.start,
                    scale: Double(pps),
                    showsPills: isSelected && model.activeItemCommand == .ducking
                )
                .frame(width: width, height: VideoStudioMetrics.musicBandHeight)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .strokeBorder(EditorTheme.timelineSelection, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .leading) { if isSelected { handle } }
        .overlay(alignment: .trailing) { if isSelected { handle } }
        .contentShape(Rectangle().inset(by: VideoStudioMetrics.bandHitInset))
        .onTapGesture { model.toggleMusic(music.id) }
        .background(dragZones(music, isSelected: isSelected))
        .offset(x: CGFloat(win.start) * pps)
        .accessibilityLabel("Music, \(music.displayName), from second \(Int(win.start)) to \(Int(win.start + win.duration))")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(EditorTheme.timelineSelection)
            .frame(width: 4, height: VideoStudioMetrics.musicBandHeight - 8)
    }

    @ViewBuilder
    private func dragZones(_ music: MusicTrack, isSelected: Bool) -> some View {
        if isSelected {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("timelineContent")).insetBy(dx: 0, dy: -3)
                let handleWidth: CGFloat = 22
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(kind: .musicLeadingHandle(music.id), rect: CGRect(x: frame.minX - 14, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .musicTrailingHandle(music.id), rect: CGRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .musicBody(music.id), rect: frame.insetBy(dx: handleWidth, dy: 0)),
                    ]
                )
            }
        }
    }
}

// MARK: - Shared band pieces

/// The dashed "add" pill both empty lanes use.
private func dashedAdd(
    title: LocalizedStringKey,
    systemImage: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            Label(title, systemImage: systemImage).labelStyle(.titleOnly)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(EditorTheme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: VideoStudioMetrics.chipBandHeight)
        .background(
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.26), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
    .buttonStyle(.plain)
}

/// The music band's real waveform, mirrored around the band's centre line and
/// windowed to the track's trim so trimming visibly slices the samples.
private struct WaveformShape: Shape {
    let samples: [Float]
    var startFraction: Double = 0
    var endFraction: Double = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else {
            path.addRect(CGRect(x: 0, y: rect.midY - 0.5, width: rect.width, height: 1))
            return path
        }
        let lower = min(max(0, startFraction), 1)
        let upper = min(max(lower, endFraction), 1)
        let span = max(0.0001, upper - lower)
        let barWidth: CGFloat = 2
        let gap: CGFloat = 2
        let step = barWidth + gap
        let count = max(1, Int(rect.width / step))
        for i in 0..<count {
            let fraction = lower + Double(i) / Double(count) * span
            let sampleIndex = Int(fraction * Double(samples.count))
            let value = CGFloat(samples[min(max(0, sampleIndex), samples.count - 1)])
            let barHeight = max(2, value * (rect.height - 6))
            let x = CGFloat(i) * step + 3
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight),
                cornerSize: CGSize(width: 1, height: 1)
            )
        }
        return path
    }
}

/// A ducking bed's level on its lane (FS-12.13 §3): a white line that dips
/// under every voice — the graph's shape at the lane's height — with a
/// "−12 dB" pill on each dip while the Ducking tab is open.
struct DuckingLaneLine: View {
    let music: MusicTrack
    let dips: [ClipSoundActivity.Span]
    /// Timeline second at x = 0.
    let origin: Double
    let scale: Double
    var showsPills = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let top: CGFloat = 4
            let depthScale = (proxy.size.height - 8) / 50
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var line = Path()
                    let steps = max(2, Int(width / 2))
                    for step in 0...steps {
                        let x = width * CGFloat(step) / CGFloat(steps)
                        let gain = DuckingMath.duckGain(at: origin + Double(x) / scale, dips: dips, ducking: music.ducking)
                        let decibels = 20 * log10(max(gain, 1e-4))
                        let depth = min(CGFloat(abs(decibels)) * 26 / 12, 50) * depthScale
                        let point = CGPoint(x: x, y: top + depth)
                        if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
                    }
                    context.stroke(line, with: .color(.white), lineWidth: 1.6)
                }
                if showsPills {
                    ForEach(Array(dips.enumerated()), id: \.offset) { _, dip in
                        let x = CGFloat((dip.start + dip.end) / 2 - origin) * scale
                        if x >= 0, x <= width {
                            Text(VideoStudioCopy.decibels(music.ducking.amountDB))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: VideoStudioMetrics.duckingPill.width, height: VideoStudioMetrics.duckingPill.height)
                                .background(Capsule().fill(Color.black.opacity(0.7)))
                                .position(x: x, y: proxy.size.height - VideoStudioMetrics.duckingPill.height / 2 - 2)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
