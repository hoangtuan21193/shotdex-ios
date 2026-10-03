import SwiftUI

/// The fixed icon column at the left of the timeline: one glyph per lane, so a
/// row is identifiable at a glance even when its bands are scrolled out of view.
/// Lanes are dynamic now, so the column is built from the same lane counts the
/// content uses and rides the content's vertical offset.
struct VideoTimelineGutter: View {
    let overlayLaneCount: Int
    let musicLaneCount: Int
    /// Which lane the current selection lives in — that glyph lights up.
    let activeLane: VideoTimelineLane?
    /// The lane stack's vertical scroll offset, so the icons track their rows.
    let offsetY: CGFloat
    /// Present only on a window wide enough for a track header column; the
    /// phone's glyph strip is decorative and needs nothing to act on.
    var model: VideoStudioModel?

    @Environment(\.videoLaneMetrics) private var lanes

    private var showsControls: Bool { lanes.showsTrackControls && model != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(laneOrder, id: \.self) { lane in
                Group {
                    if showsControls, let model, lanes.gutterStyle == .badges {
                        VideoTrackBadgeRow(
                            lane: lane,
                            model: model,
                            isActive: lane == activeLane,
                            height: height(of: lane)
                        )
                    } else if showsControls, let model {
                        VideoTrackHeader(
                            lane: lane,
                            model: model,
                            isActive: lane == activeLane,
                            height: height(of: lane)
                        )
                    } else {
                        icon(lane)
                    }
                }
                .offset(y: showsControls ? laneTop(of: lane) - offsetY : top(of: lane) - offsetY)
            }
        }
        .frame(width: lanes.gutter, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        // A header carries buttons; a glyph strip carries nothing, and used to
        // swallow the vertical scroll that reveals the lanes under it.
        .allowsHitTesting(showsControls)
    }

    /// The lane's own top and height, for a header that fills its row rather
    /// than a glyph that is centred in it.
    private func laneTop(of lane: VideoTimelineLane) -> CGFloat {
        let overlayLanes = max(1, overlayLaneCount)
        switch lane {
        case .overlay(let index): return lanes.overlayLaneTop(index)
        case .video: return lanes.videoLaneTop(overlayLanes: overlayLanes)
        case .music(let index): return lanes.musicLaneTop(index, overlayLanes: overlayLanes)
        }
    }

    private func height(of lane: VideoTimelineLane) -> CGFloat {
        switch lane {
        case .overlay: lanes.overlay
        case .video: lanes.video
        case .music: lanes.music
        }
    }

    private var laneOrder: [VideoTimelineLane] {
        (0..<max(1, overlayLaneCount)).map { VideoTimelineLane.overlay($0) }
            + [.video]
            + (0..<max(1, musicLaneCount)).map { VideoTimelineLane.music($0) }
    }

    private func top(of lane: VideoTimelineLane) -> CGFloat {
        let overlayLanes = max(1, overlayLaneCount)
        switch lane {
        case .overlay(let index):
            return lanes.overlayLaneTop(index)
                + (lanes.overlay - lanes.gutterIcon) / 2
        case .video:
            return lanes.videoLaneTop(overlayLanes: overlayLanes)
                + (lanes.video - lanes.gutterIcon) / 2
        case .music(let index):
            return lanes.musicLaneTop(index, overlayLanes: overlayLanes)
                + (lanes.music - lanes.gutterIcon) / 2
        }
    }

    /// A glyph per lane — the phone's and the Duo cover's column. It is
    /// decorative: the controls for what is in a lane belong to the thing
    /// that is selected.
    private func icon(_ lane: VideoTimelineLane) -> some View {
        let isActive = lane == activeLane
        let tint = isActive ? EditorTheme.timelineSelection : EditorTheme.secondaryText
        return Image(systemName: lane.systemImage)
            .font(.system(size: lanes.gutterGlyph, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: lanes.gutterIcon, height: lanes.gutterIcon)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? EditorTheme.timelineSelection.opacity(0.14) : .clear)
            )
            .frame(width: lanes.gutter)
            .accessibilityHidden(true)
    }
}

/// One row of the timeline, in the order they stack: overlay lanes above the
/// video lane, music lanes below it.
enum VideoTimelineLane: Hashable {
    case overlay(Int)
    case video
    case music(Int)

    var systemImage: String {
        switch self {
        case .overlay: "textformat"
        case .video: "film"
        case .music: "music.note"
        }
    }

    /// What the lane holds, in the words the rest of the studio uses for it.
    var name: String {
        switch self {
        // "Text" with no context reads as an SMS in half the languages this
        // ships in; every one of these says which lane it names.
        case .overlay: String(localized: "Text", comment: "Video Studio timeline lane: the text and sticker overlay track")
        case .video: String(localized: "Video", comment: "Video Studio timeline lane: the video and photo clip track")
        case .music: String(localized: "Music", comment: "Video Studio timeline lane: the music track")
        }
    }

    /// `T1` / `V1` / `A1`, numbered the way an NLE numbers tracks: from one,
    /// per kind, in the order they stack.
    var badge: String {
        switch self {
        case .overlay(let index): "T\(index + 1)"
        case .video: "V1"
        case .music(let index): "A\(index + 1)"
        }
    }

    /// The lane as its switches name it — "Video", "Music 2" — so a second
    /// lane's Lock is not read as the first one's.
    var switchName: String {
        switch self {
        case .overlay(let index): index == 0 ? name : "\(name) \(index + 1)"
        case .video: name
        case .music(let index): index == 0 ? name : "\(name) \(index + 1)"
        }
    }
}

/// What a lane's Lock and Mute switches read and do — one source for the
/// iPad's track header and the Duo's badge column (FS-12.03b §4).
extension VideoStudioModel {
    /// Nil on a text lane and on an empty music lane: there is nothing there
    /// to hear, and a mute that does nothing is the control to avoid.
    func muteAction(for lane: VideoTimelineLane) -> (() -> Void)? {
        switch lane {
        case .overlay: nil
        case .video: { self.toggleVideoTrackMuted() }
        case .music(let index):
            musicTracks(inLane: index).isEmpty ? nil : { self.toggleMusicLaneMuted(index) }
        }
    }

    func isLaneMuted(_ lane: VideoTimelineLane) -> Bool {
        switch lane {
        case .overlay: false
        case .video: isVideoTrackMuted
        case .music(let index): isMusicLaneMuted(index)
        }
    }
}

extension VideoTimelineLane {
    /// "Lock Video" — the label stays while the trait says whether it is on,
    /// so the switch is found by one name in either state.
    var lockLabel: String { VideoStudioCopy.lockLane(switchName) }
    var muteLabel: String { VideoStudioCopy.muteLane(switchName) }
}

/// The Duo inner display's badge column (FS-12.03b §4): the lane's badge,
/// then Lock and Mute as 28pt discs on white 10 %, each answering 32pt wide
/// by the lane's height. No name — 100pt is all the 951pt window spares.
/// A text lane has Lock only; Mute shows only where there is sound.
struct VideoTrackBadgeRow: View {
    let lane: VideoTimelineLane
    @Bindable var model: VideoStudioModel
    let isActive: Bool
    let height: CGFloat

    private typealias Lanes = VideoStudioMetrics.Lanes

    var body: some View {
        let isLocked = model.isLaneLocked(lane)
        let isMuted = model.isLaneMuted(lane)
        let tint = isActive ? EditorTheme.timelineSelection : EditorTheme.secondaryText
        ZStack(alignment: .leading) {
            Text(lane.badge)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(isActive ? Color.black : .white)
                .frame(width: Lanes.badgeWidth, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? EditorTheme.timelineSelection : EditorTheme.trackChip)
                )
                .offset(x: Lanes.badgeColumnMargin)
                .accessibilityLabel(Text(verbatim: "\(lane.badge), \(lane.name)"))
            switchDisc(
                systemImage: isLocked ? "lock.fill" : "lock.open",
                isOn: isLocked,
                onTint: EditorTheme.accent,
                label: lane.lockLabel
            ) { model.toggleLaneLock(lane) }
                .offset(x: Lanes.badgeLockX - (Lanes.badgeTouchWidth - Lanes.badgeDisc) / 2)
            if let mute = model.muteAction(for: lane) {
                switchDisc(
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isOn: isMuted,
                    onTint: EditorTheme.timelineDestructive,
                    label: lane.muteLabel,
                    action: mute
                )
                .offset(x: Lanes.badgeMuteX - (Lanes.badgeTouchWidth - Lanes.badgeDisc) / 2)
            }
        }
        .foregroundStyle(tint)
        .frame(width: Lanes.badgeColumnWidth, height: height, alignment: .leading)
    }

    private func switchDisc(
        systemImage: String,
        isOn: Bool,
        onTint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Lanes.badgeGlyph, weight: .medium))
                .foregroundStyle(isOn ? onTint : Color.white.opacity(0.75))
                .frame(width: Lanes.badgeDisc, height: Lanes.badgeDisc)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .frame(width: Lanes.badgeTouchWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One track header: the lane's badge and name, with lock and mute beside
/// them. Resolve, Final Cut and LumaFusion all put these two switches on the
/// track rather than in an inspector, and for the same reason — they are what
/// you reach for *while* cutting, to stop a drag landing in the wrong lane or
/// to hear the music without the camera audio under it.
///
/// A lane taller than `stackedHeight` gets the name over the buttons; a
/// shorter one puts everything on one line, because a 34pt text lane has no
/// room for two rows and a clipped label is worse than a missing one.
struct VideoTrackHeader: View {
    let lane: VideoTimelineLane
    @Bindable var model: VideoStudioModel
    let isActive: Bool
    let height: CGFloat

    /// Below this a header is one row.
    private static let stackedHeight: CGFloat = 56

    private var isStacked: Bool { height >= Self.stackedHeight }

    /// A track's own controls cannot be taller than the track: a hit shape
    /// that spills upward steals the taps of the lane above it. So these get
    /// the full 44 on a tall lane and the lane's height on a short one —
    /// the same constraint every NLE's track header lives with.
    private var buttonWidth: CGFloat { isStacked ? AppTheme.Size.minTouch : 34 }
    private var buttonHeight: CGFloat { min(AppTheme.Size.minTouch, max(20, height - 6)) }
    private var isLocked: Bool { model.isLaneLocked(lane) }
    private var tint: Color { isActive ? EditorTheme.timelineSelection : EditorTheme.secondaryText }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: 3) {
                    title
                    HStack(spacing: 2) {
                        lockButton
                        if muteAction != nil { muteButton }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 2) {
                    title
                    Spacer(minLength: 0)
                    lockButton
                    if muteAction != nil { muteButton }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(width: VideoStudioMetrics.Lanes.trackHeaderWidth, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isActive ? EditorTheme.timelineSelection.opacity(0.12) : EditorTheme.trackChip)
                .padding(.trailing, 4)
        )
    }

    private var title: some View {
        HStack(spacing: 4) {
            Text(lane.badge)
                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(tint))
            Text(lane.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(lane.badge), \(lane.name)"))
    }

    private var lockButton: some View {
        Button { model.toggleLaneLock(lane) } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isLocked ? EditorTheme.accent : EditorTheme.dimText)
                .frame(width: buttonWidth, height: buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: lane.lockLabel))
        .accessibilityAddTraits(isLocked ? .isSelected : [])
    }

    private var muteAction: (() -> Void)? { model.muteAction(for: lane) }
    private var isMuted: Bool { model.isLaneMuted(lane) }

    private var muteButton: some View {
        Button { muteAction?() } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isMuted ? EditorTheme.timelineDestructive : EditorTheme.dimText)
                .frame(width: buttonWidth, height: buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: lane.muteLabel))
        .accessibilityAddTraits(isMuted ? .isSelected : [])
    }
}
