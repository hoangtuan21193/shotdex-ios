import SwiftUI

/// The multi-track timeline (spec §4): a fixed icon gutter, a scrolling content
/// area whose centre carries a fixed playhead, and a thin scrollbar. Scrolling
/// scrubs; playback scrolls; pinch rescales; the transport's fit button zooms
/// the whole project into view.
struct VideoTimelineView: View {
    @Bindable var model: VideoStudioModel

    let onAddText: () -> Void
    let onAddFilter: () -> Void
    let onAddMusic: () -> Void
    let onAddMedia: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onTransition: (Int) -> Void

    @State private var pps: CGFloat = VideoStudioMetrics.defaultPointsPerSecond
    @State private var pinchStartPPS: CGFloat = VideoStudioMetrics.defaultPointsPerSecond
    @State private var dragZones: [TimelineDragZone] = []
    @State private var activeDrag: TimelineActiveDrag?
    @State private var viewportWidth: CGFloat = 393
    @State private var lastHapticSecond = 0

    /// Timeline width plus trailing room so the end-of-row add buttons (up to a
    /// dashed pill) are fully scrollable into view, never half-clipped (§4.6).
    private var contentWidth: CGFloat { max(model.totalDuration, 0.1) * pps + 130 }

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let halfWidth = VideoStudioMetrics.rowAreaHalfWidth(screenWidth: screenWidth)
            let visibleLeftTime = model.currentTime - Double(halfWidth / pps)

            HStack(spacing: 0) {
                VideoTimelineGutter(activeTrack: activeTrack)
                    .zIndex(2)

                VideoTimelineScroller(
                    contentWidth: contentWidth,
                    currentTime: model.currentTime,
                    pps: pps,
                    dragZones: dragZones,
                    onScrubStart: { model.beginScrub() },
                    onScrubTime: { scrub(to: $0) },
                    onScrubEnd: { model.endScrub(at: $0) },
                    onPinch: handlePinch,
                    onZoneDrag: handleZoneDrag
                ) {
                    TimelineTracksContent(
                        model: model,
                        pps: pps,
                        contentWidth: contentWidth,
                        visibleLeftTime: visibleLeftTime,
                        activeDrag: activeDrag,
                        onAddText: onAddText,
                        onAddFilter: onAddFilter,
                        onAddMusic: onAddMusic,
                        onAddMedia: onAddMedia,
                        onEditText: onEditText,
                        onTransition: onTransition
                    )
                    .onPreferenceChange(TimelineDragZonesKey.self) { dragZones = $0 }
                }
            }
            .overlay(alignment: .topLeading) {
                playhead.offset(x: VideoStudioMetrics.playheadX(screenWidth: screenWidth) - 1)
            }
            .overlay(alignment: .topLeading) { scrollbar(screenWidth: screenWidth) }
            .onAppear { viewportWidth = screenWidth }
            .onChange(of: screenWidth) { viewportWidth = $0 }
        }
        .frame(height: VideoStudioMetrics.timelineHeight)
        .background(EditorTheme.background)
        .clipped()
        .onChange(of: model.fitToWindowToken) { _ in fitToWindow() }
    }

    private var activeTrack: VideoStudioMetrics.Track? {
        switch model.inspectorTarget {
        case .clip: .video
        case .music: .music
        case .text: model.selectedOverlay?.kind == .text ? .text : nil
        case .none: nil
        }
    }

    // MARK: Playhead & scrollbar

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
        .frame(height: VideoStudioMetrics.trackAreaBottom - VideoStudioMetrics.timelineTopPadding)
        .padding(.top, VideoStudioMetrics.timelineTopPadding)
        .offset(x: -4.5)  // centre the 11pt cap on the 2pt line
        .allowsHitTesting(false)
    }

    private func scrollbar(screenWidth: CGFloat) -> some View {
        let left = VideoStudioMetrics.gutterWidth
        let width = screenWidth - left - 8
        let total = max(model.totalDuration, 0.1)
        let viewportTime = Double((screenWidth - left) / pps)
        let thumbFraction = min(1, viewportTime / total)
        let posFraction = total > 0 ? min(1 - thumbFraction, max(0, model.currentTime / total - thumbFraction / 2)) : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.07)).frame(width: width, height: 3)
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: max(20, width * CGFloat(thumbFraction)), height: 3)
                .offset(x: width * CGFloat(posFraction))
        }
        .offset(x: left, y: VideoStudioMetrics.trackAreaBottom + 1)
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
        case .ended:
            break
        }
    }

    private func fitToWindow() {
        let rowWidth = viewportWidth - VideoStudioMetrics.gutterWidth
        guard model.totalDuration > 0.1, rowWidth > 0 else { return }
        let target = rowWidth / CGFloat(model.totalDuration)
        withAnimation(EditorTheme.animation) {
            pps = min(
                max(target, VideoStudioMetrics.pointsPerSecondRange.lowerBound),
                VideoStudioMetrics.pointsPerSecondRange.upperBound
            )
        }
    }

    // MARK: Zone drag commit

    private func handleZoneDrag(_ kind: TimelineDragZone.Kind, _ phase: TimelineZoneDragPhase) {
        switch phase {
        case .changed(let tx):
            activeDrag = TimelineActiveDrag(kind: kind, translationX: tx)
        case .ended(let tx):
            commit(kind, translationX: tx)
            activeDrag = nil
        case .cancelled:
            activeDrag = nil
        }
    }

    private func commit(_ kind: TimelineDragZone.Kind, translationX: CGFloat) {
        let delta = Double(translationX) / Double(pps)
        switch kind {
        case .textBody(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let limit = max(0, model.totalDuration - base)
            model.pushUndo()
            model.setOverlayTiming(start: min(max(0, timed.start + delta), limit), duration: timed.duration, forOverlay: id)
        case .textLeadingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let end = timed.start + base
            let newStart = min(max(0, timed.start + delta), end - 0.5)
            model.pushUndo()
            model.setOverlayTiming(start: newStart, duration: end - newStart, forOverlay: id)
        case .textTrailingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let newDuration = min(max(0.5, base + delta), max(0.5, model.totalDuration - timed.start))
            model.pushUndo()
            model.setOverlayTiming(start: timed.start, duration: newDuration, forOverlay: id)
        case .clipReorder(let id):
            guard let sourceIndex = model.recipe.clips.firstIndex(where: { $0.id == id }) else { return }
            let placements = model.clipPlacements
            guard sourceIndex < placements.count else { return }
            let widths = placements.map { max(16, Double($0.duration) * Double(pps)) }
            let origin = widths.prefix(sourceIndex).reduce(0, +)
            let centre = origin + widths[sourceIndex] / 2 + Double(translationX)
            let target = VideoTimelineMath.dropIndex(forOffset: centre, widths: widths)
            if target != sourceIndex {
                model.pushUndo()
                model.moveClip(from: sourceIndex, to: target)
            }
        case .clipLeadingHandle, .clipTrailingHandle:
            break  // clips trim via the inspector Duration slider (spec §5.2)
        }
    }
}
