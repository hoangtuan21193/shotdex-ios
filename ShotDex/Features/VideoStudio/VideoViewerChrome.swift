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
    /// The quick-adjust strip under the frame. Resolve keeps its own behind a
    /// tools icon in the viewer rather than always on, and for the reason
    /// this screen just proved: on a 669pt-tall window every band that is
    /// always there comes out of the frame.
    var isToolStripOpen: Bool = false
    let onToggleMediaPool: () -> Void
    let onToggleInspector: () -> Void
    let onToggleToolStrip: () -> Void

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

            toggle(
                systemImage: "wand.and.rays",
                isOn: isToolStripOpen,
                label: Text("Quick Adjust", comment: "Video Studio: shows or hides the quick slider strip under the frame"),
                action: onToggleToolStrip
            )

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

    /// The marker the playhead is sitting on, if any — the button changes
    /// from "add one" to "recolour this one" rather than stacking a second
    /// dot on the same pixel.
    private var markerHere: TimedMarker? { model.marker(near: model.currentTime) }

    var body: some View {
        HStack(spacing: 2) {
            glyph("scissors", label: Text("Split at Playhead", comment: "Video Studio transport: cuts the clip under the playhead in two")) {
                model.splitClipUnderPlayhead()
            }
            glyph("snowflake", label: Text("Freeze Frame", comment: "Video Studio transport: holds the frame under the playhead as a still")) {
                model.freezeUnderPlayhead()
            }
            // Resolve's Cut page keeps this pair here, to the left of the
            // transport, for the same reason: the commonest trim is losing a
            // run-up or a tail, and it should be one tap.
            glyph(
                "arrow.left.to.line",
                label: Text("Trim Start to Playhead", comment: "Video Studio transport: throws away the part of the clip before the playhead")
            ) {
                model.trimToPlayhead(.start)
            }
            glyph(
                "arrow.right.to.line",
                label: Text("Trim End to Playhead", comment: "Video Studio transport: throws away the part of the clip after the playhead")
            ) {
                model.trimToPlayhead(.end)
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

            // Markers, the way Resolve's Cut page has them: drop one where
            // you are, then step between them.
            glyph("chevron.left.2", label: Text("Previous Marker", comment: "Video Studio transport")) {
                model.seekToMarker(after: false)
            }
            glyph(
                markerHere == nil ? "mappin" : "mappin.circle.fill",
                label: markerHere == nil
                    ? Text("Add Marker", comment: "Video Studio transport: pins a note at the playhead")
                    : Text("Change Marker Colour", comment: "Video Studio transport: cycles the colour of the marker at the playhead"),
                isOn: markerHere != nil
            ) {
                if let marker = markerHere {
                    model.cycleMarkerColor(marker.id)
                } else {
                    model.addMarker()
                }
            }
            glyph("chevron.right.2", label: Text("Next Marker", comment: "Video Studio transport")) {
                model.seekToMarker(after: true)
            }

            Spacer(minLength: 0)

            glyph("rectangle.compress.vertical", label: Text("Fit Timeline to Window", comment: "Video Studio transport: rescales the timeline so the whole project fits")) {
                model.fitToWindow()
            }
            Text(VideoStudioMetrics.timecode(model.currentTime))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                // The one thing in this row that must never shrink: a
                // truncated timecode ("00:0…") is worse than no timecode.
                // The spacers either side give way instead.
                .fixedSize()
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

                // Markers ride the ruler, not the clips: trimming a shot
                // must not drag every note along with it.
                ForEach(model.recipe.markers) { marker in
                    Circle()
                        .fill(VideoMarkerPalette.color(marker.clampedColorIndex))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.5))
                        .offset(
                            x: CGFloat(marker.time / total) * width - 3.5,
                            y: -VideoStudioMetrics.timelineOverviewHeight / 2 + 3.5
                        )
                        .onTapGesture { model.seek(to: marker.time) }
                        .accessibilityLabel(Text("Marker at \(VideoStudioMetrics.timecode(marker.time))", comment: "Video Studio: a note pinned to a point on the timeline"))
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

/// The fixed marker colours. A marker colour is a category, and a colour
/// picker would turn a category into a decision; Resolve offers a set, so
/// does this.
enum VideoMarkerPalette {
    static func color(_ index: Int) -> Color {
        switch TimedMarker.palette[min(max(0, index), TimedMarker.palette.count - 1)] {
        case "green": EditorTheme.histogramGreen
        case "yellow": .yellow
        case "red": EditorTheme.clipping
        case "purple": .purple
        default: EditorTheme.histogramBlue
        }
    }
}

/// The phone's transport row — the same commands as `VideoTransportBar`, in
/// one row that fits a 320pt screen.
///
/// The rule this follows: **a phone gets every tool the tablet has; what
/// changes is the shape and the route to it.** The desk row spreads sixteen
/// controls across 700pt. Here the four that are held down — frame and edit
/// stepping — stay inline where a thumb can repeat them, and the ones that
/// are chosen once (split, freeze, trim, markers, loop, fit) move into an
/// overflow menu, which is what iOS does with a row that will not fit.
///
/// No play pill: the frame already carries a 56pt play button while paused,
/// and a tap on the stage pauses. Two play buttons in 320pt is one too many.
struct VideoCompactTransportBar: View {
    @Bindable var model: VideoStudioModel

    private var frame: Double { 1.0 / VideoStudioMetrics.timecodeFrameRate }
    private var markerHere: TimedMarker? { model.marker(near: model.currentTime) }

    var body: some View {
        HStack(spacing: 0) {
            glyph("backward.end.fill", label: Text("Go to Start", comment: "Video Studio transport")) {
                model.seek(to: 0)
            }
            glyph("backward.frame.fill", label: Text("Back a Frame", comment: "Video Studio transport")) {
                model.seek(to: model.currentTime - frame)
            }
            glyph("forward.frame.fill", label: Text("Forward a Frame", comment: "Video Studio transport")) {
                model.seek(to: model.currentTime + frame)
            }
            glyph("forward.end.fill", label: Text("Go to End", comment: "Video Studio transport")) {
                model.seek(to: model.totalDuration)
            }

            Spacer(minLength: 0)

            Text(VideoStudioMetrics.timecode(model.currentTime))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                // Never shrink: a truncated timecode is worse than none.
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                        .fill(EditorTheme.trackChip)
                )
                .accessibilityLabel(Text("Playhead at \(VideoStudioMetrics.timecode(model.currentTime))", comment: "Video Studio transport: VoiceOver label for the timecode read-out"))

            Spacer(minLength: 0)

            overflow
        }
        .padding(.horizontal, 6)
        .frame(height: VideoStudioMetrics.compactTransportHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    /// Everything the desk row shows as its own button. Grouped the way the
    /// row is: what cuts, what loops, where the notes are, what the view does.
    private var overflow: some View {
        Menu {
            Section {
                Button {
                    model.splitClipUnderPlayhead()
                } label: {
                    Label {
                        Text("Split at Playhead", comment: "Video Studio transport: cuts the clip under the playhead in two")
                    } icon: {
                        Image(systemName: "scissors")
                    }
                }
                Button {
                    model.freezeUnderPlayhead()
                } label: {
                    Label {
                        Text("Freeze Frame", comment: "Video Studio transport: holds the frame under the playhead as a still")
                    } icon: {
                        Image(systemName: "snowflake")
                    }
                }
                Button {
                    model.trimToPlayhead(.start)
                } label: {
                    Label {
                        Text("Trim Start to Playhead", comment: "Video Studio transport: throws away the part of the clip before the playhead")
                    } icon: {
                        Image(systemName: "arrow.left.to.line")
                    }
                }
                Button {
                    model.trimToPlayhead(.end)
                } label: {
                    Label {
                        Text("Trim End to Playhead", comment: "Video Studio transport: throws away the part of the clip after the playhead")
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                    }
                }
            }

            Section {
                Button {
                    model.seekToMarker(after: false)
                } label: {
                    Label {
                        Text("Previous Marker", comment: "Video Studio transport")
                    } icon: {
                        Image(systemName: "chevron.left.2")
                    }
                }
                Button {
                    if let marker = markerHere {
                        model.cycleMarkerColor(marker.id)
                    } else {
                        model.addMarker()
                    }
                } label: {
                    Label {
                        markerHere == nil
                            ? Text("Add Marker", comment: "Video Studio transport: pins a note at the playhead")
                            : Text("Change Marker Colour", comment: "Video Studio transport: cycles the colour of the marker at the playhead")
                    } icon: {
                        Image(systemName: markerHere == nil ? "mappin" : "mappin.circle.fill")
                    }
                }
                Button {
                    model.seekToMarker(after: true)
                } label: {
                    Label {
                        Text("Next Marker", comment: "Video Studio transport")
                    } icon: {
                        Image(systemName: "chevron.right.2")
                    }
                }
            }

            Section {
                Toggle(isOn: $model.loopsPlayback) {
                    Label {
                        Text("Loop Playback", comment: "Video Studio transport: restarts the project when it reaches the end")
                    } icon: {
                        Image(systemName: "repeat")
                    }
                }
                Toggle(isOn: $model.snapsToEdits) {
                    Label {
                        Text("Snap to Edits", comment: "Video Studio transport: the playhead settles on a cut instead of near it")
                    } icon: {
                        Image(systemName: "magnet")
                    }
                }
                Button {
                    model.fitToWindow()
                } label: {
                    Label {
                        Text("Fit Timeline to Window", comment: "Video Studio transport: rescales the timeline so the whole project fits")
                    } icon: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                }
            }

            Section {
                tracksMenu
            }

            if let id = model.selectedClipID {
                Section {
                    Button(role: .destructive) {
                        model.deleteClip(id)
                    } label: {
                        Label {
                            Text("Delete Clip", comment: "Video Studio transport: removes the selected clip")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: AppTheme.Size.minTouch, height: 28)
                .videoHitTarget(drawnHeight: 28)
        }
        .accessibilityLabel(Text("More Playhead Tools", comment: "Video Studio transport: the overflow menu on a phone"))
        .accessibilityIdentifier("transport.more")
    }

    /// Lock and mute, per track.
    ///
    /// A desk window puts these on the track header, where an NLE puts them.
    /// A phone has no header column — its gutter is a glyph strip that must
    /// stay untouchable, because anything hit-testable there swallows the
    /// vertical drag that reveals the lanes under it. So the same two
    /// switches live here, one submenu per lane, named the way the timeline
    /// names them.
    private var tracksMenu: some View {
        Menu {
            ForEach(laneOrder, id: \.self) { lane in
                Section(laneTitle(lane)) {
                    Toggle(isOn: Binding(
                        get: { model.isLaneLocked(lane) },
                        set: { _ in model.toggleLaneLock(lane) }
                    )) {
                        Label {
                            Text("Lock", comment: "Video Studio track menu: stops the track being selected or dragged")
                        } icon: {
                            Image(systemName: "lock")
                        }
                    }
                    if let mute = muteBinding(lane) {
                        Toggle(isOn: mute) {
                            Label {
                                Text("Mute", comment: "Video Studio track menu: silences the track")
                            } icon: {
                                Image(systemName: "speaker.slash")
                            }
                        }
                    }
                }
            }
        } label: {
            Label {
                Text("Tracks", comment: "Video Studio transport menu: lock and mute, per track")
            } icon: {
                Image(systemName: "square.stack.3d.up")
            }
        }
    }

    /// The same order the timeline stacks them in.
    private var laneOrder: [VideoTimelineLane] {
        (0..<max(1, model.overlayLaneCount)).map { VideoTimelineLane.overlay($0) }
            + [.video]
            + (0..<max(1, model.musicLaneCount)).map { VideoTimelineLane.music($0) }
    }

    /// `V1 Video`, `A2 Music` — the badge the track header shows, so the two
    /// places name the same track the same way.
    private func laneTitle(_ lane: VideoTimelineLane) -> String {
        let badge = switch lane {
        case .overlay(let index): "T\(index + 1)"
        case .video: "V1"
        case .music(let index): "A\(index + 1)"
        }
        return "\(badge) · \(lane.name)"
    }

    /// Nil on a text lane, and on a music lane with nothing in it: a mute
    /// switch over silence is the control the track header exists to avoid.
    private func muteBinding(_ lane: VideoTimelineLane) -> Binding<Bool>? {
        switch lane {
        case .overlay:
            return nil
        case .video:
            return Binding(
                get: { model.isVideoTrackMuted },
                set: { _ in model.toggleVideoTrackMuted() }
            )
        case .music(let index):
            guard !model.musicTracks(inLane: index).isEmpty else { return nil }
            return Binding(
                get: { model.isMusicLaneMuted(index) },
                set: { _ in model.toggleMusicLaneMuted(index) }
            )
        }
    }

    private func glyph(
        _ systemImage: String,
        label: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: AppTheme.Size.minTouch, height: 28)
                .videoHitTarget(drawnHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
