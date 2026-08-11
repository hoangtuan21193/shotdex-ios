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

/// The scrolling timeline content: ruler + the four track rows, positioned by
/// time. Every band sits at `start * pps`; the ruler and rows share the same
/// content width so they scroll as one. Selection is timeline-blue; the empty
/// background clears the selection on tap.
struct TimelineTracksContent: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let contentWidth: CGFloat
    /// Timeline time at the visible left edge — drives sticky band labels.
    let visibleLeftTime: Double
    let activeDrag: TimelineActiveDrag?

    let onAddText: () -> Void
    let onAddFilter: () -> Void
    let onAddMusic: () -> Void
    let onAddMedia: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onTransition: (Int) -> Void

    private var placements: [VideoTimelineMath.Placement] { model.clipPlacements }

    var body: some View {
        VStack(spacing: 0) {
            TimelineRuler(totalDuration: model.totalDuration, pps: pps, visibleLeftTime: visibleLeftTime)
                .frame(width: contentWidth, height: VideoStudioMetrics.rulerHeight)
                .padding(.top, VideoStudioMetrics.timelineTopPadding)
                .padding(.bottom, VideoStudioMetrics.rulerToTracks)

            row(.text) { TextTrack(model: model, pps: pps, visibleLeftTime: visibleLeftTime, activeDrag: activeDrag, onAdd: onAddText) }
            spacer
            row(.video) { VideoTrack(model: model, pps: pps, placements: placements, activeDrag: activeDrag, onAddMedia: onAddMedia, onTransition: onTransition) }
            spacer
            row(.filter) { FilterTrack(model: model, pps: pps, visibleLeftTime: visibleLeftTime, onAdd: onAddFilter) }
            spacer
            row(.music) { MusicTrackRow(model: model, pps: pps, visibleLeftTime: visibleLeftTime, onAdd: onAddMusic) }
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.clearSelection() }
        .coordinateSpace(name: "timelineContent")
    }

    private var spacer: some View {
        Color.clear.frame(height: VideoStudioMetrics.trackSpacing)
    }

    private func row<Content: View>(
        _ track: VideoStudioMetrics.Track,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(width: contentWidth, height: track.height, alignment: .leading)
    }
}

// MARK: - Ruler

/// Second ticks (major every 1s with a label, minor every 0.5s). A label that
/// reaches the right edge of the row area is right-aligned instead of left
/// (spec §4.3).
private struct TimelineRuler: View {
    let totalDuration: Double
    let pps: CGFloat
    let visibleLeftTime: Double

    var body: some View {
        Canvas { context, size in
            guard pps > 0 else { return }
            let seconds = Int(totalDuration.rounded(.up))
            // Half-second ticks.
            var half = 0.0
            while half <= Double(seconds) + 0.5 {
                let x = CGFloat(half) * pps
                if x > size.width + 1 { break }
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

// MARK: - Text track

/// One bar per timed text overlay. Drag the body to move, a handle to resize;
/// the drags arrive from the scroller's zone pan via `activeDrag`.
private struct TextTrack: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let visibleLeftTime: Double
    let activeDrag: TimelineActiveDrag?
    let onAdd: () -> Void

    private static let minimumDuration = 0.5

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(model.recipe.overlays.filter { $0.overlay.kind == .text }) { timed in
                bar(timed)
            }
            if model.recipe.overlays.contains(where: { $0.overlay.kind == .text }) {
                addButtonAfterLast
            } else {
                emptyAddButton(title: "Text", systemImage: "textformat", action: onAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func window(_ timed: TimedOverlay) -> (start: Double, duration: Double) {
        let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
        guard let activeDrag else { return (timed.start, base) }
        let delta = Double(activeDrag.translationX) / Double(pps)
        switch activeDrag.kind {
        case .textBody(let id) where id == timed.id:
            let limit = max(0, model.totalDuration - base)
            return (min(max(0, timed.start + delta), limit), base)
        case .textLeadingHandle(let id) where id == timed.id:
            let end = timed.start + base
            let newStart = min(max(0, timed.start + delta), end - Self.minimumDuration)
            return (newStart, end - newStart)
        case .textTrailingHandle(let id) where id == timed.id:
            let duration = min(
                max(Self.minimumDuration, base + delta),
                max(Self.minimumDuration, model.totalDuration - timed.start)
            )
            return (timed.start, duration)
        default:
            return (timed.start, base)
        }
    }

    @ViewBuilder
    private func bar(_ timed: TimedOverlay) -> some View {
        let isSelected = model.selectedOverlayID == timed.id
        let win = window(timed)
        let width = max(28, CGFloat(win.duration) * pps)
        let stickyInset = min(max(0, CGFloat(visibleLeftTime - win.start) * pps), width - 40)

        chipBody(
            icon: "textformat",
            title: timed.overlay.text.isEmpty ? String(localized: "Text") : timed.overlay.text,
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
        .accessibilityLabel("Text, \(timed.overlay.text), from second \(Int(win.start)) to \(Int(win.start + win.duration))")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(EditorTheme.timelineSelection)
            .frame(width: 4, height: VideoStudioMetrics.chipBandHeight - 6)
    }

    private var addButtonAfterLast: some View {
        let last = model.recipe.overlays.filter { $0.overlay.kind == .text }
            .map { ($0.duration ?? max(0.1, model.totalDuration - $0.start)) + $0.start }
            .max() ?? 0
        return dashedAdd(title: "Text", systemImage: "textformat", action: onAdd)
            .offset(x: CGFloat(last) * pps + 8)
    }

    @ViewBuilder
    private func dragZones(_ timed: TimedOverlay, isSelected: Bool) -> some View {
        if isSelected {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("timelineContent")).insetBy(dx: 0, dy: -6)
                let handleWidth: CGFloat = 22
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(kind: .textLeadingHandle(timed.id), rect: CGRect(x: frame.minX - 14, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .textTrailingHandle(timed.id), rect: CGRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth + 14, height: frame.height)),
                        TimelineDragZone(kind: .textBody(timed.id), rect: frame.insetBy(dx: handleWidth, dy: 0)),
                    ]
                )
            }
        }
    }

    private func emptyAddButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        dashedAdd(title: title, systemImage: systemImage, action: action)
    }

    private func dashedAdd(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
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

// MARK: - Filter track

/// One full-span bar for the global filter (a look applies to the whole video),
/// or a dashed add button when the filter is Original.
private struct FilterTrack: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let visibleLeftTime: Double
    let onAdd: () -> Void

    var body: some View {
        let isOriginal = model.recipe.filter == .original
        Group {
            if isOriginal {
                Button(action: onAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Filter").font(.system(size: 10.5, weight: .semibold))
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
            } else {
                let width = max(40, CGFloat(model.totalDuration) * pps)
                let stickyInset = min(max(0, CGFloat(visibleLeftTime) * pps), width - 60)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        }
                    HStack(spacing: 4) {
                        Image(systemName: "camera.filters").font(.system(size: 12, weight: .semibold))
                        Text(model.recipe.filter.displayName).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 6 + max(0, stickyInset))
                    .padding(.trailing, 6)
                }
                .frame(width: width, height: VideoStudioMetrics.chipBandHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: onAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Music track

private struct MusicTrackRow: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let visibleLeftTime: Double
    let onAdd: () -> Void

    var body: some View {
        Group {
            if model.recipe.music != nil {
                musicBar
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Music").font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(EditorTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: VideoStudioMetrics.musicBandHeight)
                    .background(
                        RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.26), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicName: String {
        switch model.recipe.music?.source {
        case .bundled(let id): MusicTrackCatalog.track(id: id)?.displayName ?? String(localized: "Music")
        case .imported(_, let name): name
        case nil: ""
        }
    }

    private var musicBar: some View {
        let isSelected = model.isMusicSelected
        let width = max(40, CGFloat(model.totalDuration) * pps)
        let stickyInset = min(max(0, CGFloat(visibleLeftTime) * pps), width - 60)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .fill(isSelected ? EditorTheme.timelineSelection.opacity(0.22) : Color.white.opacity(0.06))
            WaveformShape(samples: model.musicWaveform)
                .fill(isSelected ? EditorTheme.timelineSelection : Color.white.opacity(0.42))
            HStack(spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 9, weight: .bold))
                Text(musicName).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
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
        .contentShape(Rectangle())
        .onTapGesture { model.isMusicSelected ? model.clearSelection() : model.selectMusic() }
        .accessibilityLabel("Music, \(musicName)")
    }
}

/// The music band's real waveform, mirrored around the band's centre line.
private struct WaveformShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else {
            path.addRect(CGRect(x: 0, y: rect.midY - 0.5, width: rect.width, height: 1))
            return path
        }
        let barWidth: CGFloat = 2
        let gap: CGFloat = 2
        let step = barWidth + gap
        let count = max(1, Int(rect.width / step))
        for i in 0..<count {
            let sampleIndex = Int(Double(i) / Double(count) * Double(samples.count))
            let value = CGFloat(samples[min(sampleIndex, samples.count - 1)])
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
