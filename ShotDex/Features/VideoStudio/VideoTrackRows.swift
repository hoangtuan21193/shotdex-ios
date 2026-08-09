import Photos
import SwiftUI

/// The drag zones the track rows publish for the scroller's UIKit pan
/// (selected text bar + handles, the selected clip cell).
struct TimelineDragZonesKey: PreferenceKey {
    static let defaultValue: [TimelineDragZone] = []
    static func reduce(value: inout [TimelineDragZone], nextValue: () -> [TimelineDragZone]) {
        value.append(contentsOf: nextValue())
    }
}

/// Shared vertical geometry so the scrolling tracks and the fixed left icon
/// rail line up. Every track is the same height (the reference design), and
/// the rail's icon for track `i` sits at `trackTop(i)`.
enum TimelineMetrics {
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let rulerHeight: CGFloat = 16
    static let rowSpacing: CGFloat = 4
    static let trackHeight: CGFloat = 34
    static let railWidth: CGFloat = 34
    static let trackCount = 5

    static var totalHeight: CGFloat {
        topPadding + rulerHeight + rowSpacing
            + CGFloat(trackCount) * trackHeight
            + CGFloat(trackCount - 1) * rowSpacing
            + bottomPadding
    }

    /// Y of track index `i`'s top edge, from the timeline's top.
    static func trackTop(_ index: Int) -> CGFloat {
        topPadding + rulerHeight + rowSpacing
            + CGFloat(index) * (trackHeight + rowSpacing)
    }
}

/// The stacked track rows hosted inside the timeline scroller. One VStack in
/// one scroller — every row scrolls together by construction. Order matches
/// the left icon rail: Text, Filter, Effect, Video, Audio.
struct TimelineTracksContent: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let contentWidth: CGFloat
    let activeDrag: TimelineActiveDrag?
    let onEditText: (PhotoOverlay) -> Void

    var body: some View {
        let placements = model.clipPlacements
        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
            TimelineRulerRow(totalDuration: model.totalDuration, pps: pps)
                .frame(width: contentWidth, height: TimelineMetrics.rulerHeight, alignment: .leading)
            TextTrackRow(model: model, pps: pps, activeDrag: activeDrag, onEditText: onEditText)
                .frame(width: contentWidth, height: TimelineMetrics.trackHeight, alignment: .leading)
            FilterTrackRow(model: model)
                .frame(width: contentWidth, height: TimelineMetrics.trackHeight, alignment: .leading)
            EffectTrackRow(model: model, pps: pps, placements: placements)
                .frame(width: contentWidth, height: TimelineMetrics.trackHeight, alignment: .leading)
            VideoClipsTrackRow(
                model: model,
                pps: pps,
                placements: placements,
                activeDrag: activeDrag
            )
            .frame(width: contentWidth, height: TimelineMetrics.trackHeight, alignment: .leading)
            AudioTrackRow(model: model)
                .frame(width: contentWidth, height: TimelineMetrics.trackHeight, alignment: .leading)
        }
        .padding(.top, TimelineMetrics.topPadding)
        .padding(.bottom, TimelineMetrics.bottomPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            // Empty timeline tap: clear selection, close any panel.
            model.selectedClipID = nil
            model.selectedOverlayID = nil
            withAnimation(EditorTheme.panelSpring) { model.activePanel = nil }
        }
        .coordinateSpace(name: "timelineContent")
    }
}

/// The fixed left column of track icons (Text / Filter / Effect / Video /
/// Audio). Does not scroll; opaque so timeline content slides under it. Tap
/// an icon to open that track's panel.
struct TimelineIconRail: View {
    @Bindable var model: VideoStudioModel

    private struct RailItem {
        let systemImage: String
        let action: () -> Void
    }

    var body: some View {
        let items = railItems
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button(action: item.action) {
                    // Plain glyph, no coloured background (matches reference).
                    Image(systemName: item.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: TimelineMetrics.railWidth, height: TimelineMetrics.trackHeight)
                }
                .buttonStyle(.plain)
                .offset(y: TimelineMetrics.trackTop(index))
            }
        }
        .frame(
            width: TimelineMetrics.railWidth,
            height: TimelineMetrics.totalHeight,
            alignment: .topLeading
        )
        .background(EditorTheme.background)
    }

    private func selectClipUnderPlayhead() {
        guard let index = VideoTimelineMath.clipIndex(
            at: model.currentTime, placements: model.clipPlacements
        ) else {
            model.selectedClipID = model.recipe.clips.first?.id
            return
        }
        model.selectedClipID = model.recipe.clips[index].id
    }

    private var railItems: [RailItem] {
        [
            RailItem(systemImage: "textformat") { open(.text) },
            RailItem(systemImage: "camera.filters") { open(.filter) },
            RailItem(systemImage: "sparkles") {
                selectClipUnderPlayhead()
                if model.selectedClipID != nil { open(.effect) }
            },
            RailItem(systemImage: "video.fill") {
                selectClipUnderPlayhead()
                if model.selectedClipID != nil { open(.clipEdit) }
            },
            RailItem(systemImage: "music.note") { open(.music) },
        ]
    }

    private func open(_ panel: VideoStudioModel.TimelinePanel) {
        withAnimation(EditorTheme.panelSpring) { model.activePanel = panel }
    }
}

// MARK: - Ruler

/// Second ticks with labels every `labelStep` seconds — the smallest step
/// whose labels stay at least 44 pt apart at the current scale.
struct TimelineRulerRow: View {
    let totalDuration: Double
    let pps: CGFloat

    var body: some View {
        Canvas { context, size in
            guard pps > 0 else { return }
            let labelStep = [1, 2, 5, 10, 30, 60].first {
                CGFloat($0) * pps >= 44
            } ?? 60
            let seconds = Int(totalDuration.rounded(.up))
            for second in 0...max(seconds, 1) {
                let x = CGFloat(second) * pps
                guard x <= size.width + 1 else { break }
                let isLabeled = second % labelStep == 0
                let tickHeight: CGFloat = isLabeled ? 5 : 3
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.white.opacity(isLabeled ? 0.45 : 0.22)),
                    lineWidth: 1
                )
                if isLabeled {
                    context.draw(
                        Text(rulerLabel(second))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45)),
                        at: CGPoint(x: x + 3, y: size.height - 11),
                        anchor: .leading
                    )
                }
            }
        }
    }

    private func rulerLabel(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)s"
    }
}

// MARK: - Text track

/// One bar per timed text overlay. Drag the body to move its start; drag a
/// handle to resize; a nil duration (until-the-end) materializes on first
/// resize. The drags arrive from the scroller's UIKit pan (`activeDrag`);
/// this row only renders drafts and publishes the drag zones.
struct TextTrackRow: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let activeDrag: TimelineActiveDrag?
    let onEditText: (PhotoOverlay) -> Void

    private static let minimumDuration = 0.5
    private static let barColor = Color(red: 0.95, green: 0.35, blue: 0.62)

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(model.recipe.overlays) { timed in
                bar(timed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bar's window with any in-flight drag applied.
    private func resolvedWindow(_ timed: TimedOverlay) -> (start: Double, duration: Double) {
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
        let window = resolvedWindow(timed)
        let width = max(24, CGFloat(window.duration) * pps)

        HStack(spacing: 4) {
            Image(systemName: "textformat")
                .font(.system(size: 8, weight: .bold))
            Text(timed.overlay.text.isEmpty ? String(localized: "Text") : timed.overlay.text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .frame(width: width, height: 20, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Self.barColor.opacity(isSelected ? 0.95 : 0.65))
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected { handle.offset(x: -8) }
        }
        .overlay(alignment: .trailing) {
            if isSelected { handle.offset(x: 8) }
        }
        .onTapGesture {
            model.selectedOverlayID = isSelected ? nil : timed.id
        }
        .background(dragZoneReporter(timed, isSelected: isSelected))
        .offset(x: CGFloat(window.start) * pps)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: 4, height: 14)
    }

    /// The selected bar publishes three zones: leading handle strip, body,
    /// trailing handle strip (the handles hang 14 pt past each end).
    @ViewBuilder
    private func dragZoneReporter(_ timed: TimedOverlay, isSelected: Bool) -> some View {
        if isSelected {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("timelineContent"))
                    .insetBy(dx: 0, dy: -4)
                let handleWidth: CGFloat = 22
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(
                            kind: .textLeadingHandle(timed.id),
                            rect: CGRect(
                                x: frame.minX - 14, y: frame.minY,
                                width: handleWidth + 14, height: frame.height
                            )
                        ),
                        TimelineDragZone(
                            kind: .textTrailingHandle(timed.id),
                            rect: CGRect(
                                x: frame.maxX - handleWidth, y: frame.minY,
                                width: handleWidth + 14, height: frame.height
                            )
                        ),
                        TimelineDragZone(
                            kind: .textBody(timed.id),
                            rect: frame.insetBy(dx: handleWidth, dy: 0)
                        ),
                    ]
                )
            }
        }
    }
}

// MARK: - Effect track

/// Spans mirroring the placement of every clip with an effect. Not draggable
/// by definition — a per-clip effect covers exactly its clip.
struct EffectTrackRow: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let placements: [VideoTimelineMath.Placement]

    private static let barColor = Color(red: 0.62, green: 0.42, blue: 0.95)

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(model.recipe.clips.enumerated()), id: \.element.id) { index, clip in
                if clip.effect != .none, index < placements.count {
                    span(clip, placement: placements[index])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func span(_ clip: VideoClip, placement: VideoTimelineMath.Placement) -> some View {
        Text(clip.effect.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(width: max(20, CGFloat(placement.duration) * pps), height: 16, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Self.barColor.opacity(model.selectedClipID == clip.id ? 0.95 : 0.65))
            )
            .offset(x: CGFloat(placement.start) * pps)
            .onTapGesture {
                model.selectedClipID = clip.id
                withAnimation(EditorTheme.panelSpring) { model.activePanel = .effect }
            }
    }
}

// MARK: - Filter track

/// One full-span bar for the global filter — tap opens the filter panel.
struct FilterTrackRow: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        let isOriginal = model.recipe.filter == .original
        HStack(spacing: 4) {
            Image(systemName: "camera.filters")
                .font(.system(size: 8, weight: .bold))
            Text(isOriginal
                ? String(localized: "Filter")
                : String(localized: "Filter · \(model.recipe.filter.displayName)"))
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(isOriginal ? 0.45 : 1))
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 16)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.25, green: 0.55, blue: 0.6).opacity(isOriginal ? 0.3 : 0.65))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(EditorTheme.panelSpring) { model.activePanel = .filter }
        }
    }
}

// MARK: - Video clips track

/// The main track: filmstrip cells at their placements, ⊕ transition buttons
/// on every boundary, tap-select; dragging the SELECTED cell reorders (the
/// drag arrives from the scroller's UIKit pan via `activeDrag`).
struct VideoClipsTrackRow: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let placements: [VideoTimelineMath.Placement]
    let activeDrag: TimelineActiveDrag?

    private let cellHeight: CGFloat = TimelineMetrics.trackHeight

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(model.recipe.clips.enumerated()), id: \.element.id) { index, clip in
                if index < placements.count {
                    cell(clip, placement: placements[index])
                }
            }
            if model.mode == .multiClip {
                transitionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: model.selectedClipID)
    }

    private func cellWidth(_ placement: VideoTimelineMath.Placement) -> CGFloat {
        max(16, CGFloat(placement.duration) * pps)
    }

    private func dragOffset(_ clip: VideoClip) -> CGFloat {
        guard let activeDrag, case .clipReorder(let id) = activeDrag.kind, id == clip.id
        else { return 0 }
        return activeDrag.translationX
    }

    private func cell(_ clip: VideoClip, placement: VideoTimelineMath.Placement) -> some View {
        let isSelected = model.selectedClipID == clip.id
        let isDragging = dragOffset(clip) != 0
        let width = cellWidth(placement)

        return ClipFilmstrip(
            assetID: clip.assetID,
            photoLibrary: model.photoLibrary,
            width: width,
            height: cellHeight
        )
        .overlay(alignment: .bottomTrailing) {
            Text(String(format: "%.1fs", clip.effectiveDuration))
                .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .padding(3)
        }
        .overlay(alignment: .bottomLeading) {
            if clip.kind == .video && clip.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white)
                    .padding(3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isSelected ? EditorTheme.accent : Color.white.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .frame(width: width, height: cellHeight)
        .offset(x: CGFloat(placement.start) * pps + dragOffset(clip))
        .scaleEffect(isDragging ? 1.06 : 1)
        .zIndex(isDragging ? 3 : 0)
        .shadow(color: isDragging ? .black.opacity(0.5) : .clear, radius: 8)
        .onTapGesture {
            model.selectedClipID = isSelected ? nil : clip.id
            if !isSelected, model.selectedOverlayID != nil {
                model.selectedOverlayID = nil
            }
        }
        // Only the SELECTED cell is a reorder zone: making every cell
        // draggable would eat plain scrubbing over the clips row. Select
        // first, then drag the highlighted cell to move it.
        .background(reorderZoneReporter(clip, isSelected: isSelected))
    }

    @ViewBuilder
    private func reorderZoneReporter(_ clip: VideoClip, isSelected: Bool) -> some View {
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

    /// ⊕ on every boundary, centred where the two neighbours meet. The glyph
    /// mirrors the configured transition; an accent ring marks a non-none one.
    private var transitionButtons: some View {
        ForEach(0..<max(0, min(model.recipe.transitions.count, placements.count - 1)), id: \.self) { index in
            let transition = model.recipe.transitions[index]
            let x = CGFloat((placements[index].end + placements[index + 1].start) / 2) * pps
            Button {
                model.selectedOverlayID = nil
                withAnimation(EditorTheme.panelSpring) { model.activePanel = .transition(index) }
            } label: {
                Image(systemName: transitionGlyph(transition.kind))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white))
                    .overlay {
                        if transition.kind != .none {
                            Circle().strokeBorder(EditorTheme.accent, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .offset(x: x - 13, y: (cellHeight - 26) / 2)
            .zIndex(2)
        }
    }

    private func transitionGlyph(_ kind: VideoTransitionKind) -> String {
        switch kind {
        case .none: "plus"
        case .crossfade: "square.filled.on.square"
        case .fadeBlack: "moon.fill"
        case .slideLeft: "arrow.left.square"
        case .slideRight: "arrow.right.square"
        case .wipe: "rectangle.lefthalf.filled"
        case .zoom: "plus.magnifyingglass"
        }
    }
}

/// A clip cell's picture: the shared local-only thumbnail repeated every
/// 56 pt so long clips read as filmstrips without extra image requests.
struct ClipFilmstrip: View {
    let assetID: String
    let photoLibrary: PhotoLibraryService
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 0) {
            let count = max(1, Int((width / height).rounded(.up)))
            ForEach(0..<count, id: \.self) { _ in
                Rectangle()
                    .fill(EditorTheme.control)
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
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
            ) { result in
                if let result { image = result }
            }
        }
    }
}

// MARK: - Audio track

/// The music bed: a green bar with a deterministic fake waveform, or an
/// "Add music" pill when there is none. Tap opens the music panel.
struct AudioTrackRow: View {
    @Bindable var model: VideoStudioModel

    private static let barColor = Color(red: 0.22, green: 0.72, blue: 0.42)

    var body: some View {
        Group {
            if model.recipe.music != nil {
                musicBar
            } else {
                addMusicPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicName: String {
        switch model.recipe.music?.source {
        case .bundled(let id):
            MusicTrackCatalog.track(id: id)?.displayName ?? String(localized: "Music")
        case .imported(_, let name):
            name
        case nil:
            ""
        }
    }

    private var musicBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Self.barColor.opacity(0.55))
            Canvas { context, size in
                // Deterministic pseudo-waveform: bar heights from a sine hash
                // of the index — stable across frames, no state.
                var x: CGFloat = 3
                var index = 0
                while x < size.width - 3 {
                    let unit = abs(sin(Double(index) * 12.9898 + 78.233))
                    let barHeight = 4 + CGFloat(unit) * (size.height - 10)
                    context.fill(
                        Path(roundedRect: CGRect(
                            x: x, y: (size.height - barHeight) / 2,
                            width: 2, height: barHeight
                        ), cornerRadius: 1),
                        with: .color(.white.opacity(0.55))
                    )
                    x += 4
                    index += 1
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .bold))
                Text(musicName)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.leading, 5)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(EditorTheme.panelSpring) { model.activePanel = .music }
        }
    }

    private var addMusicPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
            Text("Add music")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(EditorTheme.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(EditorTheme.panelSpring) { model.activePanel = .music }
        }
    }
}
