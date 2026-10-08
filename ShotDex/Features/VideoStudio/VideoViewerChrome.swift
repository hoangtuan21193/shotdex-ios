import SwiftUI
import ShotDexKit

/// What the frame is showing, at the head of the iPad's play row under it
/// (FS-12.03b §1): "Clip 2" in 17 semibold over nothing, then "under
/// playhead" in 13. The frame is the one region on screen that does not say
/// what it shows, and with the pool open there are two pictures on screen.
struct VideoPlayheadName: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if model.isSelectingClips {
                // A group open (FS-12.11 §3, board F1_IL_MultiSelect): the
                // head of the row says what the inspector is editing.
                Text(verbatim: VideoStudioCopy.clipsSelected(model.selectedClipIDs.count))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(verbatim: clipTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(VideoStudioCopy.underPlayhead)
                    .font(.system(size: 13))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// What the playhead is over, named the way the timeline names it.
    private var clipTitle: String {
        guard let index = model.clipIndexUnderPlayhead,
              index < model.recipe.clips.count
        else {
            return String(localized: "No Clip", comment: "Video Studio viewer header: the playhead is past the end of the project")
        }
        // The same name the session footer gives a selected clip.
        return VideoItemTitle.clipName(model.recipe.clips[index].kind, index: index)
    }
}

/// The transport's fifteen controls (FS-12.03b §2), in their four groups.
/// Every row that draws them is built from this list, so no window can
/// drop one: the Duo's single row, the iPad's play row and tool row.
enum VideoTransportControl: CaseIterable, Hashable {
    case split, freeze, trimStart, trimEnd, delete
    case goToStart, backFrame, play, forwardFrame, goToEnd, loop
    case previousMarker, addMarker, nextMarker
    case fit

    enum Group { case edit, play, marker, view }

    var group: Group {
        switch self {
        case .split, .freeze, .trimStart, .trimEnd, .delete: .edit
        case .goToStart, .backFrame, .play, .forwardFrame, .goToEnd, .loop: .play
        case .previousMarker, .addMarker, .nextMarker: .marker
        case .fit: .view
        }
    }

    static func controls(in group: Group) -> [Self] { allCases.filter { $0.group == group } }

    /// The iPad's play row under the frame: the six play controls (Before
    /// and After follows them, FS-12.15).
    static let playRow = controls(in: .play)
    /// The iPad's tool row over the timeline: the playhead edits, the
    /// markers, Fit — with the timecode before Fit.
    static let toolRow = controls(in: .edit) + controls(in: .marker) + controls(in: .view)
}

/// One transport control, `size` square (44 on the iPad, 36 on the Duo's
/// inner display). The edit group acts on the clip **under the playhead**,
/// not the selected item — that is the command row's job (FS-12.03b §2).
struct VideoTransportButton: View {
    @Bindable var model: VideoStudioModel
    let control: VideoTransportControl
    var size: CGFloat = VideoStudioDeskGeometry.toolRowHeight
    /// Play's disc: 48 in the iPad's play row, the button's size elsewhere.
    var playDisc: CGFloat?

    /// One frame at the rate the timecode is counted in.

    /// The marker the playhead is sitting on, if any — the button changes
    /// from "add one" to "recolour this one" rather than stacking a second
    /// dot on the same pixel.
    private var markerHere: TimedMarker? { model.marker(near: model.currentTime) }

    var body: some View {
        switch control {
        case .split:
            glyph("scissors", label: Text("Split at Playhead", comment: "Video Studio transport: cuts the clip under the playhead in two")) {
                model.splitClipUnderPlayhead()
            }
        case .freeze:
            glyph("snowflake", label: Text("Freeze Frame", comment: "Video Studio transport: holds the frame under the playhead as a still")) {
                model.freezeUnderPlayhead()
            }
        case .trimStart:
            glyph("arrow.left.to.line", label: Text("Trim Start to Playhead", comment: "Video Studio transport: throws away the part of the clip before the playhead")) {
                model.trimToPlayhead(.start)
            }
        case .trimEnd:
            glyph("arrow.right.to.line", label: Text("Trim End to Playhead", comment: "Video Studio transport: throws away the part of the clip after the playhead")) {
                model.trimToPlayhead(.end)
            }
        case .delete:
            glyph(
                "trash",
                label: Text(VideoStudioCopy.deleteClipAtPlayhead),
                isEnabled: model.canDeleteClipUnderPlayhead,
                isDestructive: true
            ) {
                model.deleteClipUnderPlayhead()
            }
        case .goToStart:
            glyph("backward.end", label: Text("Go to Start", comment: "Video Studio transport")) {
                model.seek(to: 0)
            }
        case .backFrame:
            glyph("backward.frame", label: Text("Back a Frame", comment: "Video Studio transport")) {
                model.stepFrames(-1)
            }
        case .play:
            // White 12 %, not accent: accent is Export's alone (FS-12.03b §2).
            let disc = playDisc ?? size
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: disc * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: disc, height: disc)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
                    // J / L at 2× or 4× (FS-12.17b §3): the rate on a white
                    // 30×15 tag at the button's corner.
                    .overlay(alignment: .topTrailing) {
                        if let rate = VideoShuttle.label(for: model.shuttleRate) {
                            Text(verbatim: rate)
                                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .frame(width: 30, height: 15)
                                .background(Capsule().fill(Color.white))
                                .offset(x: 10, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.isPlaying
                    ? Text("Pause", comment: "Video Studio transport")
                    : Text("Play", comment: "Video Studio transport")
            )
            .accessibilityValue(Text(verbatim: VideoShuttle.label(for: model.shuttleRate) ?? ""))
        case .forwardFrame:
            glyph("forward.frame", label: Text("Forward a Frame", comment: "Video Studio transport")) {
                model.stepFrames(1)
            }
        case .goToEnd:
            glyph("forward.end", label: Text("Go to End", comment: "Video Studio transport")) {
                model.seek(to: model.totalDuration)
            }
        case .loop:
            glyph(
                "repeat",
                label: Text("Loop Playback", comment: "Video Studio transport: restarts the project when it reaches the end"),
                isOn: model.loopsPlayback
            ) {
                model.loopsPlayback.toggle()
            }
        case .previousMarker:
            glyph("chevron.left.2", label: Text("Previous Marker", comment: "Video Studio transport")) {
                model.seekToMarker(after: false)
            }
        case .addMarker:
            glyph(
                markerHere == nil ? "mappin" : "mappin.circle.fill",
                label: markerHere == nil
                    ? Text("Add Marker", comment: "Video Studio transport: pins a note at the playhead")
                    : Text(VideoStudioCopy.changeMarkerColor),
                isOn: markerHere != nil
            ) {
                if let marker = markerHere {
                    model.cycleMarkerColor(marker.id)
                } else {
                    model.addMarker()
                }
            }
        case .nextMarker:
            glyph("chevron.right.2", label: Text("Next Marker", comment: "Video Studio transport")) {
                model.seekToMarker(after: true)
            }
        case .fit:
            glyph("arrow.left.and.right", label: Text("Fit Timeline to Window", comment: "Video Studio transport: rescales the timeline so the whole project fits")) {
                model.fitToWindow()
            }
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
                .font(.system(size: size * 0.43, weight: .regular))
                .foregroundStyle(tint(isEnabled: isEnabled, isDestructive: isDestructive))
                .frame(width: size, height: size)
                .background(Circle().fill(isOn ? VideoStudioMetrics.openCellFill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func tint(isEnabled: Bool, isDestructive: Bool) -> Color {
        guard isEnabled else { return Color.white.opacity(0.28) }
        return isDestructive ? EditorTheme.timelineDestructive : .white
    }
}

/// `0:08.4 / 0:24.0` — the playhead, then the length dimmed, in mono; one
/// form on every device (FS-12.03b §2, FS-12.07 §2). Never shrinks: a
/// truncated timecode is worse than none.
struct VideoTransportTimecode: View {
    @Bindable var model: VideoStudioModel
    var size: CGFloat = 17

    var body: some View {
        let text = VideoStudioMetrics.compactTransportReadout(playhead: model.currentTime, length: model.totalDuration)
        return (Text(text.playhead).foregroundStyle(.white)
            + Text(text.length).foregroundStyle(.white.opacity(0.4)))
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .fixedSize()
            .accessibilityLabel(Text(
                "Playhead at \(text.playhead) of \(VideoStudioMetrics.compactTimecode(model.totalDuration))",
                tableName: VideoStudioCopy.table,
                comment: "Video Studio transport: VoiceOver label for the phone read-out — playhead, then the project's length"
            ))
    }
}

/// Before and After at the end of the iPad's play row (FS-12.03b §2,
/// FS-12.15 §4): 44, transparent, white 14 % while on. A tap turns the
/// compare on — Side by Side, the pool folded — or off.
struct VideoBeforeAfterButton: View {
    @Bindable var model: VideoStudioModel
    var size: CGFloat = VideoStudioDeskGeometry.beforeAfterButton

    var body: some View {
        let isOn = model.compare != nil
        Button {
            model.toggleBeforeAfter(sideBySide: true)
        } label: {
            Image(systemName: "square.split.2x1")
                .font(.system(size: size * 0.43, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(isOn ? VideoStudioMetrics.openCellFill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(VideoStudioCopy.beforeAndAfter))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("beforeAndAfterButton")
    }
}

/// The Duo inner display's disc at (148, 12) (FS-12.15 §4, AC-12): a tap
/// turns Before and After on or off; held for 0.3 s or more it is Show
/// original — both frames show Before until the finger lifts. White with
/// a black glyph when on, the dark disc when off.
struct VideoDuoCompareDisc: View {
    @Bindable var model: VideoStudioModel
    let diameter: CGFloat

    @State private var pressedAt: Date?
    @State private var isHolding = false

    var body: some View {
        let isOn = model.compare != nil
        Image(systemName: "square.split.2x1")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isOn || model.showsOriginal ? Color.black : Color.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(isOn || model.showsOriginal ? Color.white : Color.black.opacity(0.55)))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressedAt == nil {
                            pressedAt = .now
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.3))
                                guard pressedAt != nil, !isHolding else { return }
                                isHolding = true
                                model.setShowsOriginal(true)
                            }
                        }
                    }
                    .onEnded { _ in
                        if isHolding {
                            model.setShowsOriginal(false)
                        } else {
                            model.toggleBeforeAfter(sideBySide: true)
                        }
                        isHolding = false
                        pressedAt = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(VideoStudioCopy.beforeAndAfter))
            .accessibilityHint(Text("Press and hold to see the clips without edits", comment: "Hint for the Video Studio before/after control"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityAction { model.toggleBeforeAfter(sideBySide: true) }
            .accessibilityIdentifier("beforeAndAfterButton")
    }
}

/// The iPad's play row, under the frame (FS-12.03b §1–2, board IL1_Main):
/// what the frame shows at its head, the six play controls centred on the
/// stage, Before and After at the frame's trailing edge.
struct VideoPlayRow: View {
    @Bindable var model: VideoStudioModel
    /// Where the play group's centre falls, in the row's own coordinates.
    let groupMidX: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            VideoPlayheadName(model: model)
            HStack(spacing: 0) {
                ForEach(VideoTransportControl.playRow, id: \.self) { control in
                    if control == .loop { Color.clear.frame(width: 10) }
                    VideoTransportButton(model: model, control: control, playDisc: VideoStudioDeskGeometry.playRowHeight)
                }
            }
            .frame(width: VideoStudioDeskGeometry.playGroupWidth)
            .position(x: groupMidX, y: VideoStudioDeskGeometry.playRowHeight / 2)
            HStack {
                Spacer(minLength: 0)
                VideoBeforeAfterButton(model: model)
            }
        }
        .frame(height: VideoStudioDeskGeometry.playRowHeight)
    }
}

/// The timeline's tool row on the iPad, the window's whole width
/// (FS-12.03b §2, board IL1_Main): the five playhead edits, a rule, the
/// three marker controls; on the right the timecode and Fit.
struct VideoTimelineToolRow: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VideoTransportControl.controls(in: .edit), id: \.self) { control in
                VideoTransportButton(model: model, control: control)
            }
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 22)
                .padding(.horizontal, 8)
            ForEach(VideoTransportControl.controls(in: .marker), id: \.self) { control in
                VideoTransportButton(model: model, control: control)
            }
            Spacer(minLength: 0)
            VideoTransportTimecode(model: model)
                .padding(.trailing, 12)
            VideoTransportButton(model: model, control: .fit)
        }
        .padding(.horizontal, VideoStudioDeskGeometry.toolRowInset)
        .frame(height: VideoStudioDeskGeometry.toolRowHeight)
    }
}

/// The Duo inner display's transport (FS-12.03 §4, board DI1_Main): the
/// fifteen controls on one 40pt row, 36 each and 2 apart — the playhead
/// edits from the leading edge, the play controls centred on the window,
/// the markers, Fit and the timecode against the trailing edge — 36 in
/// from both edges, clear of the rounded corners.
struct VideoTransportBar: View {
    @Bindable var model: VideoStudioModel
    var height: CGFloat = VideoStudioDeskGeometry.duoTransportHeight
    /// Each control's square.
    var buttonSize: CGFloat = VideoStudioDeskGeometry.duoTransportButton

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                group(.edit)
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                group(.play)
            }
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                group(.marker)
                VideoTransportButton(model: model, control: .fit, size: buttonSize)
                VideoTransportTimecode(model: model, size: 12)
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, VideoStudioDeskGeometry.duoTransportInset)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    private func group(_ group: VideoTransportControl.Group) -> some View {
        ForEach(VideoTransportControl.controls(in: group), id: \.self) { control in
            VideoTransportButton(model: model, control: control, size: buttonSize)
        }
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

                // Every caption, a 3pt mark along the top in the speech
                // colour; the selected one in the selection colour
                // (FS-12.14 §3, AC-17).
                ForEach(model.placedCaptions, id: \.cue.id) { placed in
                    let isSelected = placed.cue.id == model.selectedCaptionID
                    Rectangle()
                        .fill(isSelected ? EditorTheme.timelineSelection : EditorTheme.timelineSpeech)
                        .frame(width: max(2, CGFloat(placed.duration / total) * width - 1), height: 3)
                        .offset(
                            x: CGFloat(placed.start / total) * width,
                            y: -VideoStudioMetrics.timelineOverviewHeight / 2 + 1.5
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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

                // Where Cut to Beat would put each cut — on the Duo's cover
                // the strip is the only timeline there is (§6).
                if let preview = model.cutToBeatPreview {
                    ForEach(preview.cuts.filter(\.moves), id: \.clipIndex) { cut in
                        Rectangle()
                            .fill(EditorTheme.timelineBeat)
                            .frame(width: 2, height: VideoStudioMetrics.timelineOverviewHeight)
                            .offset(x: CGFloat((cut.target ?? cut.time) / total) * width - 1)
                    }
                }

                // The beats of the bed whose Beats tab is open (FS-12.12 §3).
                if let music = model.recipe.musicTracks.first(where: { model.showsBeatTicks(for: $0) }),
                   let grid = model.beatGrid(for: music) {
                    let scale = Double(width) / total
                    BeatTickMarks(ticks: grid.visibleTicks(pointsPerSecond: scale), origin: 0, scale: scale, style: .overview)
                        .frame(width: width, height: VideoStudioMetrics.timelineOverviewHeight, alignment: .topLeading)
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
            // Where no timeline is drawn, a drag from Media lands here
            // (FS-12.09 §5): the whole project across the strip's width.
            .onAppear { publishDropGeometry(geo.frame(in: .global)) }
            .onChange(of: geo.frame(in: .global)) { _, frame in publishDropGeometry(frame) }
            .onChange(of: model.totalDuration) { publishDropGeometry(geo.frame(in: .global)) }
            .onDisappear { model.overviewDropGeometry = nil }
        }
        .frame(height: VideoStudioMetrics.timelineOverviewHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(EditorTheme.background)
        .accessibilityElement()
        .accessibilityLabel(Text("Project Overview", comment: "Video Studio: the whole-project strip above the timeline"))
        .accessibilityValue(Text(VideoStudioMetrics.timecode(model.currentTime, fps: model.recipe.frameRate.rawValue)))
        .accessibilityAdjustableAction { direction in
            let step = max(model.totalDuration / 20, 0.5)
            model.seek(to: model.currentTime + (direction == .increment ? step : -step))
        }
    }

    private func publishDropGeometry(_ frame: CGRect) {
        model.overviewDropGeometry = VideoDropGeometry(
            frame: frame.insetBy(dx: 0, dy: -8),
            lineBand: frame,
            mapping: .overview(totalDuration: model.totalDuration)
        )
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

    private var markerHere: TimedMarker? { model.marker(near: model.currentTime) }

    var body: some View {
        HStack(spacing: 0) {
            // Two steps either side of the read-out (FS-12.07 §2): the frame
            // steps are what a thumb taps over and over, so each sits next
            // to the number it moves.
            glyph("backward.end.fill", label: Text("Go to Start", comment: "Video Studio transport")) {
                model.seek(to: 0)
            }
            glyph("backward.frame.fill", label: Text("Back a Frame", comment: "Video Studio transport")) {
                model.stepFrames(-1)
            }

            Spacer(minLength: 0)
            readout
            Spacer(minLength: 0)

            glyph("forward.frame.fill", label: Text("Forward a Frame", comment: "Video Studio transport")) {
                model.stepFrames(1)
            }
            glyph("forward.end.fill", label: Text("Go to End", comment: "Video Studio transport")) {
                model.seek(to: model.totalDuration)
            }
            overflow
        }
        .padding(.horizontal, VideoStudioMetrics.compactTransportInset)
        .frame(height: VideoStudioMetrics.compactTransportHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    /// `0:08.4 / 0:24.0` — the playhead, then the length dimmed. Never
    /// shrinks: a truncated timecode is worse than none.
    private var readout: some View {
        let text = VideoStudioMetrics.compactTransportReadout(playhead: model.currentTime, length: model.totalDuration)
        return (Text(text.playhead).foregroundStyle(.white)
            + Text(text.length).foregroundStyle(.white.opacity(0.4)))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .fixedSize()
            .accessibilityLabel(Text(
                "Playhead at \(text.playhead) of \(VideoStudioMetrics.compactTimecode(model.totalDuration))",
                tableName: VideoStudioCopy.table,
                comment: "Video Studio transport: VoiceOver label for the phone read-out — playhead, then the project's length"
            ))
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
                            : Text(VideoStudioCopy.changeMarkerColor)
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
                precisionMenu
            }

            // Auto Captions where the window has no media pool (FS-12.14 §3
            // names a Text tool panel the phone does not have — open
            // question in the captions plan); Edit Captions once there is a
            // lane.
            Section {
                Button {
                    Task { await model.startAutoCaptions() }
                } label: {
                    Label {
                        Text(model.hasCaptionLane ? VideoStudioCopy.editCaptions : VideoStudioCopy.autoCaptions)
                    } icon: {
                        Image(systemName: "captions.bubble")
                    }
                }
                .disabled(!model.canAutoCaption && !model.hasCaptionLane)
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
                .frame(width: VideoStudioMetrics.compactTransportButton, height: VideoStudioMetrics.compactTransportButton)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More Playhead Tools", comment: "Video Studio transport: the overflow menu on a phone"))
        .accessibilityIdentifier("transport.more")
    }

    /// PRECISION (FS-12.17 §7): the device's two frame switches, in the ⋯
    /// on a phone and the Duo's cover — the panel is hidden while trimming,
    /// and the phone has everything the iPad has.
    private var precisionMenu: some View {
        @Bindable var preferences = VideoInputPreferences.shared
        return Menu {
            Toggle(isOn: $preferences.frameStepHaptics) {
                Text(verbatim: VideoStudioCopy.frameStepsWithHaptics)
            }
            Toggle(isOn: $preferences.frameZoomOnPinch) {
                Text(verbatim: VideoStudioCopy.frameZoomOnPinch)
            }
        } label: {
            Label {
                Text(verbatim: VideoStudioCopy.precision)
            } icon: {
                Image(systemName: "dial.low")
            }
        }
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
        (model.hasCaptionLane ? [.captions] : [])
            + (0..<max(1, model.overlayLaneCount)).map { VideoTimelineLane.overlay($0) }
            + [.video]
            + (0..<max(1, model.musicLaneCount)).map { VideoTimelineLane.music($0) }
    }

    /// `V1 Video`, `A2 Music` — the badge the track header shows, so the two
    /// places name the same track the same way.
    private func laneTitle(_ lane: VideoTimelineLane) -> String {
        let badge = switch lane {
        case .captions: "C1"
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
        case .captions, .overlay:
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
                .frame(width: VideoStudioMetrics.compactTransportButton, height: VideoStudioMetrics.compactTransportButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
