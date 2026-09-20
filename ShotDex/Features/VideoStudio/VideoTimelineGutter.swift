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

    @Environment(\.videoLaneMetrics) private var lanes

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(laneOrder, id: \.self) { lane in
                icon(lane)
                    .offset(y: top(of: lane) - offsetY)
            }
        }
        .frame(width: lanes.gutter, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
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
                + (lanes.overlay - VideoStudioMetrics.gutterIconSize) / 2
        case .video:
            return lanes.videoLaneTop(overlayLanes: overlayLanes)
                + (lanes.video - VideoStudioMetrics.gutterIconSize) / 2
        case .music(let index):
            return lanes.musicLaneTop(index, overlayLanes: overlayLanes)
                + (lanes.music - VideoStudioMetrics.gutterIconSize) / 2
        }
    }

    /// A glyph on a phone; on a tablet the lane's name under it, because a
    /// 13pt icon at arm's length is a track you count rather than read. The
    /// column stays decorative either way — the controls for what is in a
    /// lane belong to the thing that is selected, in the inspector.
    private func icon(_ lane: VideoTimelineLane) -> some View {
        let isActive = lane == activeLane
        let tint = isActive ? EditorTheme.timelineSelection : EditorTheme.secondaryText
        return VStack(spacing: 2) {
            Image(systemName: lane.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: VideoStudioMetrics.gutterIconSize, height: VideoStudioMetrics.gutterIconSize)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? EditorTheme.timelineSelection.opacity(0.14) : .clear)
                )
            if showsLaneNames {
                Text(lane.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: lanes.gutter)
        .accessibilityHidden(true)
    }

    /// Only where the column is wide enough to hold a word without clipping
    /// it — the phone's 30pt is not.
    private var showsLaneNames: Bool { lanes.gutter >= 56 }
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
}
