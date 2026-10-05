import SwiftUI

/// C1 (FS-12.14 §3): the caption lane above the text lanes, on every window
/// with room for it — the iPad (44, blocks as tall as the lane) and the Duo
/// (34, blocks 28). A block is white 10 %, `r-track`, 12 semibold; the
/// selected one `timelineSelection` at 22 % with a 1.5pt inner rule; the
/// clips still being read wear a striped "Transcribing…" block.
struct VideoCaptionLaneRow: View {
    @Bindable var model: VideoStudioModel
    let pps: CGFloat
    let visibleLeftTime: Double
    let activeDrag: TimelineActiveDrag?

    @Environment(\.videoLaneMetrics) private var lanes

    private var blockHeight: CGFloat { lanes.gutterStyle == .headers ? lanes.caption : 28 }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(pendingSpans, id: \.start) { span in
                pendingBlock(span)
            }
            ForEach(model.placedCaptions, id: \.cue.id) { placed in
                block(placed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Where the run has not been yet: the planned clips not finished.
    private var pendingSpans: [(start: Double, end: Double)] {
        guard model.captions.isRunning, let state = model.recipe.captions?.recognition else { return [] }
        let placements = model.clipPlacements
        return model.recipe.clips.enumerated().compactMap { index, clip in
            guard state.remainingClipIDs.contains(clip.id), index < placements.count else { return nil }
            return (placements[index].start, placements[index].end)
        }
    }

    private func pendingBlock(_ span: (start: Double, end: Double)) -> some View {
        let width = max(24, CGFloat(span.end - span.start) * pps - 2)
        return Text(VideoStudioCopy.transcribingBlock)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: width, height: blockHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .fill(StripeFill())
            )
            .clipShape(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous))
            .offset(x: CGFloat(span.start) * pps + 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where a block is drawn: where it is, or where the finger has it.
    private func window(_ placed: CaptionTimeline.Placed) -> (start: Double, end: Double) {
        guard let activeDrag else { return (placed.start, placed.end) }
        let edge: CaptionTimeline.DragEdge
        switch activeDrag.kind {
        case .captionBody(let id) where id == placed.cue.id: edge = .body
        case .captionLeadingHandle(let id) where id == placed.cue.id: edge = .start
        case .captionTrailingHandle(let id) where id == placed.cue.id: edge = .end
        default: return (placed.start, placed.end)
        }
        let delta = Double(activeDrag.translationX) / Double(pps)
        guard let moved = CaptionTimeline.dragged(placed.cue.id, edge: edge, by: delta, in: model.recipe),
              let span = CaptionTimeline.timelineSpan(
                  sourceStart: moved.sourceStart, sourceEnd: moved.sourceEnd,
                  clip: model.recipe.clips[placed.clipIndex], placement: model.clipPlacements[placed.clipIndex]
              )
        else { return (placed.start, placed.end) }
        return span
    }

    @ViewBuilder
    private func block(_ placed: CaptionTimeline.Placed) -> some View {
        let isSelected = model.selectedCaptionID == placed.cue.id
        let span = window(placed)
        let width = max(16, CGFloat(span.end - span.start) * pps - 2)
        let sticky = min(max(0, CGFloat(visibleLeftTime - span.start) * pps), max(0, width - 30))
        Text(verbatim: placed.cue.text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.leading, 8 + sticky)
            .padding(.trailing, 6)
            .frame(width: width, height: blockHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .fill(isSelected ? EditorTheme.timelineSelection.opacity(0.22) : Color.white.opacity(0.10))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .strokeBorder(EditorTheme.timelineSelection, lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { model.selectCaption(placed.cue.id) }
            .background(dragZones(placed.cue.id, isSelected: isSelected))
            .offset(x: CGFloat(span.start) * pps + 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: placed.cue.text))
            .accessibilityValue(Text(verbatim: "\(VideoStudioMetrics.captionTime(placed.start)) → \(VideoStudioMetrics.captionTime(placed.end))"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension VideoCaptionLaneRow {
    /// The selected block's body and edges take a drag through the
    /// scroller's UIKit pan — a SwiftUI drag never starts inside it.
    @ViewBuilder
    fileprivate func dragZones(_ id: UUID, isSelected: Bool) -> some View {
        if isSelected, !model.isLaneLocked(.captions) {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("timelineContent")).insetBy(dx: 0, dy: -3)
                let handle: CGFloat = 18
                Color.clear.preference(
                    key: TimelineDragZonesKey.self,
                    value: [
                        TimelineDragZone(kind: .captionLeadingHandle(id), rect: CGRect(x: frame.minX - 10, y: frame.minY, width: handle + 10, height: frame.height)),
                        TimelineDragZone(kind: .captionTrailingHandle(id), rect: CGRect(x: frame.maxX - handle, y: frame.minY, width: handle + 10, height: frame.height)),
                        TimelineDragZone(kind: .captionBody(id), rect: frame.insetBy(dx: handle, dy: 0)),
                    ]
                )
            }
        }
    }
}

/// Diagonal stripes on white 6 % — the part of the lane still being heard.
private struct StripeFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        ImagePaint(image: Image(uiImage: Self.tile), scale: 1)
    }

    private static let tile: UIImage = {
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.withAlphaComponent(0.05).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.lineWidth = 3
            UIColor.white.withAlphaComponent(0.10).setStroke()
            path.stroke()
        }
    }()
}
