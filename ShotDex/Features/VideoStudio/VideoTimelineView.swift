import Photos
import SwiftUI

/// A zone drag in flight: which zone kind, and how far the finger has moved.
/// Rows render their draft geometry from this; the commit happens on end.
struct TimelineActiveDrag: Equatable {
    var kind: TimelineDragZone.Kind
    var translationX: CGFloat
}

/// The multi-track timeline: ruler, text/effect/filter/clips/audio rows in a
/// single horizontal scroller, a fixed centre playhead, pinch to rescale.
/// Scrolling scrubs; playback scrolls. Text-bar moves/resizes and clip
/// reordering ride a UIKit pan (see `TimelineDragZone`).
struct VideoTimelineView: View {
    @Bindable var model: VideoStudioModel
    let onEditText: (PhotoOverlay) -> Void

    /// Points per second of timeline. Default 30 puts ~20 s across 1.5
    /// screens; pinch rescales within 10…120.
    @State private var pps: CGFloat = 30
    @State private var pinchStartPPS: CGFloat = 30
    @State private var dragZones: [TimelineDragZone] = []
    @State private var activeDrag: TimelineActiveDrag?

    static let height: CGFloat = TimelineMetrics.totalHeight
    private static let ppsRange: ClosedRange<CGFloat> = 10...120
    private static let minimumTextDuration = 0.5

    var body: some View {
        ZStack {
            VideoTimelineScroller(
                contentWidth: max(model.totalDuration, 0.1) * pps,
                currentTime: model.currentTime,
                pps: pps,
                dragZones: dragZones,
                onScrubStart: { model.beginScrub() },
                onScrubTime: { model.scrub(to: $0) },
                onScrubEnd: { model.endScrub(at: $0) },
                onPinch: handlePinch,
                onZoneDrag: handleZoneDrag
            ) {
                TimelineTracksContent(
                    model: model,
                    pps: pps,
                    contentWidth: max(model.totalDuration, 0.1) * pps,
                    activeDrag: activeDrag,
                    onEditText: onEditText
                )
                .onPreferenceChange(TimelineDragZonesKey.self) { zones in
                    dragZones = zones
                }
            }

            TimelineIconRail(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)

            playhead
        }
        .frame(height: Self.height)
        .background(EditorTheme.background)
        .clipped()
    }

    private var playhead: some View {
        VStack(spacing: 2) {
            if !model.isPlaying {
                Text(timecode(model.currentTime))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white, in: Capsule())
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(.white)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .padding(.vertical, 2)
        .allowsHitTesting(false)
    }

    private func handlePinch(_ phase: TimelinePinchPhase) {
        switch phase {
        case .began:
            pinchStartPPS = pps
        case .changed(let scale):
            pps = min(max(pinchStartPPS * scale, Self.ppsRange.lowerBound), Self.ppsRange.upperBound)
        case .ended:
            break
        }
    }

    // MARK: - Zone drags

    private func handleZoneDrag(_ kind: TimelineDragZone.Kind, _ phase: TimelineZoneDragPhase) {
        switch phase {
        case .changed(let translationX):
            activeDrag = TimelineActiveDrag(kind: kind, translationX: translationX)
        case .ended(let translationX):
            commit(kind, translationX: translationX)
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
            let newStart = min(max(0, timed.start + delta), limit)
            model.pushUndo()
            model.setOverlayTiming(start: newStart, duration: timed.duration, forOverlay: id)
        case .textLeadingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let end = timed.start + base
            let newStart = min(max(0, timed.start + delta), end - Self.minimumTextDuration)
            model.pushUndo()
            // Resizing materializes a nil (until-the-end) duration.
            model.setOverlayTiming(start: newStart, duration: end - newStart, forOverlay: id)
        case .textTrailingHandle(let id):
            guard let timed = model.recipe.overlays.first(where: { $0.id == id }) else { return }
            let base = timed.duration ?? max(0.1, model.totalDuration - timed.start)
            let newDuration = min(
                max(Self.minimumTextDuration, base + delta),
                max(Self.minimumTextDuration, model.totalDuration - timed.start)
            )
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
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }
}
