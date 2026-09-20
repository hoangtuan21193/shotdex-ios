import SwiftUI
import ShotDexKit

/// The strip directly above the frame: what is under the playhead on the left,
/// the project's name in the middle, and the two view toggles — the media pool
/// and the inspector — on the right.
///
/// Every desk-shaped editor labels its viewer. Without it the frame is the one
/// region on screen that does not say what it is showing, and on a window wide
/// enough to hold a media pool the user is looking at two images at once.
struct VideoViewerHeader: View {
    @Bindable var model: VideoStudioModel
    /// Nil where the column cannot fit at all, so the button is not drawn as
    /// a control that does nothing.
    var isMediaPoolOpen: Bool?
    var isInspectorOpen: Bool?
    let onToggleMediaPool: () -> Void
    let onToggleInspector: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let isMediaPoolOpen {
                toggle(
                    systemImage: "sidebar.leading",
                    isOn: isMediaPoolOpen,
                    label: Text("Media Pool", comment: "Video Studio: shows or hides the library column"),
                    action: onToggleMediaPool
                )
            }

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(clipTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(VideoStudioMetrics.timecode(model.totalDuration))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(EditorTheme.dimText)

            if let isInspectorOpen {
                toggle(
                    systemImage: "slider.horizontal.3",
                    isOn: isInspectorOpen,
                    label: Text("Inspector", comment: "Video Studio: shows or hides the controls column"),
                    action: onToggleInspector
                )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: VideoStudioMetrics.viewerHeaderHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    /// What the playhead is over, named the way the timeline names it.
    private var clipTitle: String {
        guard let index = model.clipIndexUnderPlayhead,
              index < model.recipe.clips.count
        else {
            return String(localized: "No Clip", comment: "Video Studio viewer header: the playhead is past the end of the project")
        }
        let clip = model.recipe.clips[index]
        let position = index + 1
        switch clip.kind {
        case .video:
            return String(localized: "Clip \(position)", comment: "Video Studio viewer header: the video clip under the playhead, by its position on the track")
        case .photo:
            return String(localized: "Photo \(position)", comment: "Video Studio viewer header: the still under the playhead, by its position on the track")
        case .freeze:
            return String(localized: "Freeze \(position)", comment: "Video Studio viewer header: the held frame under the playhead, by its position on the track")
        }
    }

    private func toggle(
        systemImage: String,
        isOn: Bool,
        label: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? EditorTheme.accent : EditorTheme.secondaryText)
                .frame(width: AppTheme.Size.minTouch, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? EditorTheme.accent.opacity(0.14) : .clear)
                        .padding(.horizontal, 7)
                )
                .videoHitTarget(drawnHeight: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The transport, between the frame and the timeline: the cut tools that act
/// on the playhead on the left, the play controls in the middle, the timecode
/// on the right.
///
/// On a phone these live in the contextual panel and the command band, which
/// is right when there is one column of space. A desk window has a row of it,
/// and every editor spends that row the same way — because the tools that act
/// on *where the playhead is* belong between the thing that shows the frame
/// and the thing that moves it.
struct VideoTransportBar: View {
    @Bindable var model: VideoStudioModel

    /// One frame at the rate the timecode is counted in.
    private var frame: Double { 1.0 / VideoStudioMetrics.timecodeFrameRate }

    var body: some View {
        HStack(spacing: 2) {
            glyph("scissors", label: Text("Split at Playhead", comment: "Video Studio transport: cuts the clip under the playhead in two")) {
                model.splitClipUnderPlayhead()
            }
            glyph("snowflake", label: Text("Freeze Frame", comment: "Video Studio transport: holds the frame under the playhead as a still")) {
                model.freezeUnderPlayhead()
            }
            glyph(
                "trash",
                label: Text("Delete Clip", comment: "Video Studio transport: removes the selected clip"),
                isEnabled: model.selectedClipID != nil,
                isDestructive: true
            ) {
                if let id = model.selectedClipID { model.deleteClip(id) }
            }

            Spacer(minLength: 0)

            glyph("backward.end.fill", label: Text("Go to Start", comment: "Video Studio transport")) {
                model.seek(to: 0)
            }
            glyph("backward.frame.fill", label: Text("Back a Frame", comment: "Video Studio transport")) {
                model.seek(to: model.currentTime - frame)
            }
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 30)
                    .background(Capsule().fill(EditorTheme.accent))
                    .videoHitTarget(drawnHeight: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.isPlaying
                    ? Text("Pause", comment: "Video Studio transport")
                    : Text("Play", comment: "Video Studio transport")
            )
            glyph("forward.frame.fill", label: Text("Forward a Frame", comment: "Video Studio transport")) {
                model.seek(to: model.currentTime + frame)
            }
            glyph("forward.end.fill", label: Text("Go to End", comment: "Video Studio transport")) {
                model.seek(to: model.totalDuration)
            }
            glyph(
                "repeat",
                label: Text("Loop Playback", comment: "Video Studio transport: restarts the project when it reaches the end"),
                isOn: model.loopsPlayback
            ) {
                model.loopsPlayback.toggle()
            }

            Spacer(minLength: 0)

            glyph("rectangle.compress.vertical", label: Text("Fit Timeline to Window", comment: "Video Studio transport: rescales the timeline so the whole project fits")) {
                model.fitToWindow()
            }
            Text(VideoStudioMetrics.timecode(model.currentTime))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .fill(EditorTheme.trackChip)
                )
                .accessibilityLabel(Text("Playhead at \(VideoStudioMetrics.timecode(model.currentTime))", comment: "Video Studio transport: VoiceOver label for the timecode read-out"))
        }
        .padding(.horizontal, 8)
        .frame(height: VideoStudioMetrics.transportBarHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    private func glyph(
        _ systemImage: String,
        label: Text,
        isEnabled: Bool = true,
        isOn: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint(isEnabled: isEnabled, isOn: isOn, isDestructive: isDestructive))
                .frame(width: AppTheme.Size.minTouch, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? EditorTheme.accent.opacity(0.14) : .clear)
                        .padding(.horizontal, 5)
                )
                .videoHitTarget(drawnHeight: 30)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func tint(isEnabled: Bool, isOn: Bool, isDestructive: Bool) -> Color {
        guard isEnabled else { return EditorTheme.dimText }
        if isOn { return EditorTheme.accent }
        return isDestructive ? EditorTheme.timelineDestructive : .white
    }
}

/// The whole project in one strip, above the ruler: every clip as a block at
/// its share of the total, the playhead where it is, and the visible window of
/// the zoomed timeline drawn over the top.
///
/// The timeline below it is a viewport parked on a fixed centre playhead, so
/// at any working zoom the user can see a few seconds of a project that runs
/// minutes. This is the map that goes with it — the same job Resolve's
/// timeline overview and Final Cut's timeline index do — and dragging it seeks.
struct VideoTimelineOverview: View {
    @Bindable var model: VideoStudioModel
    /// Seconds visible in the timeline viewport, for the window rectangle.
    let visibleDuration: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(model.totalDuration, 0.001)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(EditorTheme.emptyLane)

                ForEach(Array(model.clipPlacements.enumerated()), id: \.offset) { index, placement in
                    block(index: index, placement: placement, total: total, width: width)
                }

                // The slice of the project the zoomed timeline is showing.
                if visibleDuration > 0, visibleDuration < total {
                    let windowWidth = max(6, CGFloat(visibleDuration / total) * width)
                    let centre = CGFloat(model.currentTime / total) * width
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(EditorTheme.overviewWindow, lineWidth: 1)
                        .frame(width: windowWidth)
                        .offset(x: min(max(0, centre - windowWidth / 2), width - windowWidth))
                }

                Rectangle()
                    .fill(EditorTheme.clipping)
                    .frame(width: 1.5)
                    .offset(x: CGFloat(model.currentTime / total) * width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !model.isScrubbing { model.beginScrub() }
                        model.scrub(to: seconds(at: value.location.x, width: width, total: total))
                    }
                    .onEnded { value in
                        model.endScrub(at: seconds(at: value.location.x, width: width, total: total))
                    }
            )
        }
        .frame(height: VideoStudioMetrics.timelineOverviewHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(EditorTheme.background)
        .accessibilityElement()
        .accessibilityLabel(Text("Project Overview", comment: "Video Studio: the whole-project strip above the timeline"))
        .accessibilityValue(Text(VideoStudioMetrics.timecode(model.currentTime)))
        .accessibilityAdjustableAction { direction in
            let step = max(model.totalDuration / 20, 0.5)
            model.seek(to: model.currentTime + (direction == .increment ? step : -step))
        }
    }

    /// One clip's block. Split out of the body because the whole `ZStack`
    /// with it inline is past what the type checker will solve in time.
    private func block(
        index: Int,
        placement: VideoTimelineMath.Placement,
        total: Double,
        width: CGFloat
    ) -> some View {
        let isSelected = index < model.recipe.clips.count
            && model.recipe.clips[index].id == model.selectedClipID
        let fill: Color = isSelected ? EditorTheme.timelineSelection : EditorTheme.overviewClip
        let blockWidth = max(1, CGFloat(placement.duration / total) * width - 1)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(EditorTheme.trackBorder, lineWidth: 0.5)
            )
            .frame(width: blockWidth)
            .offset(x: CGFloat(placement.start / total) * width)
    }

    private func seconds(at x: CGFloat, width: CGFloat, total: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(total, max(0, Double(x / width) * total))
    }
}
