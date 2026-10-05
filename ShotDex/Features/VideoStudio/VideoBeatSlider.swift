import SwiftUI
import UIKit

/// A still's Duration while the project snaps to a bed's beats (FS-12.12
/// §5, board F2_P_BeatDuration): the beats the still's end could land on
/// ticked along the track, the end sticking to one within 8pt of the
/// finger — one tap of the haptic, the knob and the value in the beat
/// colour, two decimals — and the line saying which beat.
struct VideoBeatSlider: View {
    @Bindable var model: VideoStudioModel
    let clip: VideoClip
    /// Where the still starts on the timeline.
    let clipStart: Double
    let grid: BeatGrid
    var isDesk = false

    @State private var drag = DragState()
    private let range = VideoClip.photoDurationRange
    private let labelWidth: CGFloat = 72

    /// Drag bookkeeping in a reference: two callbacks can land before a
    /// render (memory: a UIKit-hosted `@State` reads stale).
    final class DragState {
        var isDragging = false
        var lastTick: Int?
        var hold = BeatSliderHold()
    }

    private var snappedTick: BeatGrid.Tick? {
        grid.tick(at: clipStart + clip.photoDuration).flatMap { tick in
            model.snapDivision == .bar && !tick.isBar ? nil : tick
        }
    }

    var body: some View {
        let snapped = snappedTick
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(localized: "Duration", table: VideoStudioCopy.table, comment: "Video Studio clip panel: how long a still stays on screen"))
                    .font(.system(size: isDesk ? 17 : 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: labelWidth, alignment: .leading)
                track(snapped: snapped)
                Text(String(format: "%.2fs", clip.photoDuration))
                    .font(.system(size: isDesk ? 15 : 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(snapped != nil ? EditorTheme.timelineBeat : .white)
                    .frame(width: 54, alignment: .trailing)
            }
            .frame(height: 46)
            if let snapped {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.timelineBeat)
                    Text(VideoStudioCopy.endsOnBeat(snapped.number, at: VideoStudioCopy.beatTime(snapped.time)))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.leading, labelWidth + 8)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Duration", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: how long a still stays on screen"))
        .accessibilityValue(Text(String(format: "%.2f s", clip.photoDuration) + (snapped.map { ", " + VideoStudioCopy.onBeat($0.number) } ?? "")))
        .accessibilityAdjustableAction { direction in
            // VoiceOver steps from beat to beat.
            let next = grid.ticks
                .map { $0.time - clipStart }
                .filter { range.contains($0) }
                .sorted()
                .first { direction == .increment ? $0 > clip.photoDuration + 0.001 : false }
            let previous = grid.ticks
                .map { $0.time - clipStart }
                .filter { range.contains($0) && $0 < clip.photoDuration - 0.001 }
                .max()
            guard let target = direction == .increment ? next : previous else { return }
            model.pushUndo()
            model.setPhotoDuration(target, for: clip.id)
        }
    }

    private func track(snapped: BeatGrid.Tick?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = position(of: clip.photoDuration, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(Color.white.opacity(0.8)).frame(width: max(0, x), height: 4)
                Canvas { context, size in
                    for tick in grid.ticks where model.snapDivision == .beat || tick.isBar {
                        let duration = tick.time - clipStart
                        guard range.contains(duration) else { continue }
                        let tickX = position(of: duration, width: size.width)
                        let isOn = tick.number == snapped?.number
                        context.fill(
                            Path(CGRect(x: tickX - 0.5, y: (size.height - 18) / 2, width: 1, height: 18)),
                            with: .color(EditorTheme.timelineBeat.opacity(isOn ? 0.95 : 0.45))
                        )
                    }
                }
                .allowsHitTesting(false)
                Circle()
                    .fill(snapped != nil ? EditorTheme.timelineBeat : .white)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if snapped != nil {
                            Circle().stroke(EditorTheme.timelineBeat.opacity(0.35), lineWidth: 3).frame(width: 24, height: 24)
                        }
                    }
                    .offset(x: x - 9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in changed(to: value.location.x, width: width) }
                    .onEnded { _ in ended() }
            )
        }
    }

    private func position(of duration: Double, width: CGFloat) -> CGFloat {
        CGFloat((duration - range.lowerBound) / (range.upperBound - range.lowerBound)) * width
    }

    private func changed(to x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        if !drag.isDragging {
            drag.isDragging = true
            drag.lastTick = snappedTick?.number
            drag.hold = BeatSliderHold()
            model.beginUndoGroup()
        }
        let proposed = range.lowerBound + Double(min(max(0, x), width) / width) * (range.upperBound - range.lowerBound)
        // 8pt of track in seconds of duration.
        let tolerance = Double(VideoStudioMetrics.beatSnapTolerance / width) * (range.upperBound - range.lowerBound)
        let isFree = drag.hold.update(x: Double(x), at: CACurrentMediaTime())
        let result = isFree
            ? (duration: proposed, tick: nil)
            : grid.snappedDuration(proposed, clipStart: clipStart, division: model.snapDivision, tolerance: tolerance, range: range)
        if let tick = result.tick, tick.number != drag.lastTick {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        drag.lastTick = result.tick?.number
        model.setPhotoDuration(result.duration, for: clip.id)
    }

    private func ended() {
        drag.isDragging = false
        model.endUndoGroup()
    }
}
