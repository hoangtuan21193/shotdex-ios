import Photos
import SwiftUI

/// A zone drag in flight: which zone, and how far the finger has moved. Rows
/// render their draft geometry from this; the commit happens on end.
struct TimelineActiveDrag: Equatable {
    var kind: TimelineDragZone.Kind
    var translationX: CGFloat
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
    let activeDrag: TimelineActiveDrag?

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

        VStack(spacing: VideoStudioMetrics.laneSpacing) {
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
                .frame(width: contentWidth, height: VideoStudioMetrics.overlayLaneHeight, alignment: .leading)
            }

            VideoTrack(
                model: model,
                pps: pps,
                placements: placements,
                activeDrag: activeDrag,
                onAddMedia: onAddMedia,
                onTransition: onTransition
            )
            .frame(width: contentWidth, height: VideoStudioMetrics.videoLaneHeight, alignment: .leading)

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
                .frame(width: contentWidth, height: VideoStudioMetrics.musicLaneHeight, alignment: .leading)
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

    var body: some View {
        Canvas { context, size in
            guard pps > 0 else { return }
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
}

// MARK: - Video track

private struct VideoTrack: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let placements: [VideoTimelineMath.Placement]
    let activeDrag: TimelineActiveDrag?
    let onAddMedia: () -> Void
    let onTransition: (Int) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(model.recipe.clips.enumerated()), id: \.element.id) { index, clip in
                if index < placements.count {
                    ClipBand(model: model, clip: clip, placement: placements[index], pps: pps, reorderShift: reorderShift(clip))
                }
            }
            if model.mode == .multiClip {
                transitionChips
            }
            addMediaButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(EditorTheme.animation, value: model.selectedClipID)
    }

    private func reorderShift(_ clip: VideoClip) -> CGFloat {
        guard let activeDrag, case .clipReorder(let id) = activeDrag.kind, id == clip.id
        else { return 0 }
        return activeDrag.translationX
    }

    private var addMediaButton: some View {
        let end = (placements.last?.end ?? 0)
        return Button(action: onAddMedia) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: VideoStudioMetrics.addMediaButtonWidth, height: VideoStudioMetrics.clipCellHeight)
                .background(
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .fill(Color.white.opacity(0.12))
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
                y: (VideoStudioMetrics.clipCellHeight - VideoStudioMetrics.transitionChipSize) / 2
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
    @Bindable var model: VideoStudioModel
    let clip: VideoClip
    let placement: VideoTimelineMath.Placement
    let pps: CGFloat
    let reorderShift: CGFloat

    private var isSelected: Bool { model.selectedClipID == clip.id }
    private var width: CGFloat { max(16, CGFloat(placement.duration) * pps) }

    var body: some View {
        ClipFilmstrip(
            assetID: clip.assetID,
            photoLibrary: model.photoLibrary,
            width: width,
            height: VideoStudioMetrics.clipCellHeight
        )
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay(alignment: .bottomLeading) { corners }
        .clipShape(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? EditorTheme.timelineSelection : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        .frame(width: width, height: VideoStudioMetrics.clipCellHeight)
        .offset(x: CGFloat(placement.start) * pps + reorderShift)
        .scaleEffect(reorderShift != 0 ? 1.05 : 1)
        .zIndex(reorderShift != 0 ? 3 : 0)
        .shadow(color: reorderShift != 0 ? .black.opacity(0.5) : .clear, radius: 8)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleClip(clip.id) }
        .background(reorderZone)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var durationBadge: some View {
        Text(String(format: "%.1fs", clip.effectiveDuration))
            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .padding(3)
    }

    private var corners: some View {
        HStack(spacing: 3) {
            if clip.kind == .video, clip.isMuted {
                Image(systemName: "speaker.slash.fill").font(.system(size: 8.5))
            }
            if clip.kind == .video, clip.speed != 1 {
                Text(String(format: "%.2g×", clip.speed)).font(.system(size: 8, weight: .bold).monospacedDigit())
            }
            if clip.kind == .freeze {
                Image(systemName: "snowflake").font(.system(size: 8.5))
            }
        }
        .foregroundStyle(.white)
        .padding(3)
    }

    private var accessibilityLabel: String {
        let kind = clip.kind == .video ? "Video" : clip.kind == .freeze ? "Freeze" : "Photo"
        return "\(kind) clip, from second \(Int(placement.start)) to \(Int(placement.end))"
    }

    @ViewBuilder
    private var reorderZone: some View {
        if isSelected, model.mode == .multiClip {
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

/// A clip cell's filmstrip: one shared local thumbnail repeated so long clips
/// read as a strip without extra image requests.
struct ClipFilmstrip: View {
    let assetID: String
    let photoLibrary: PhotoLibraryService
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 0) {
            let count = max(1, Int((width / max(height, 1)).rounded(.up)))
            ForEach(0..<count, id: \.self) { _ in
                Rectangle()
                    .fill(EditorTheme.control)
                    .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                    .frame(width: height, height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
        .onAppear {
            guard image == nil,
                  let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first
            else { return }
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: 240, height: 240),
                allowNetwork: false
            ) { result in if let result { image = result } }
        }
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
