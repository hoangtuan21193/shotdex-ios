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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(lanes, id: \.self) { lane in
                icon(lane)
                    .offset(y: top(of: lane) - offsetY)
            }
        }
        .frame(width: VideoStudioMetrics.gutterWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
    }

    private var lanes: [VideoTimelineLane] {
        (0..<max(1, overlayLaneCount)).map { VideoTimelineLane.overlay($0) }
            + [.video]
            + (0..<max(1, musicLaneCount)).map { VideoTimelineLane.music($0) }
    }

    private func top(of lane: VideoTimelineLane) -> CGFloat {
        let overlayLanes = max(1, overlayLaneCount)
        switch lane {
        case .overlay(let index):
            return VideoStudioMetrics.overlayLaneTop(index)
                + (VideoStudioMetrics.overlayLaneHeight - VideoStudioMetrics.gutterIconSize) / 2
        case .video:
            return VideoStudioMetrics.videoLaneTop(overlayLanes: overlayLanes)
                + (VideoStudioMetrics.videoLaneHeight - VideoStudioMetrics.gutterIconSize) / 2
        case .music(let index):
            return VideoStudioMetrics.musicLaneTop(index, overlayLanes: overlayLanes)
                + (VideoStudioMetrics.musicLaneHeight - VideoStudioMetrics.gutterIconSize) / 2
        }
    }

    private func icon(_ lane: VideoTimelineLane) -> some View {
        let isActive = lane == activeLane
        return Image(systemName: lane.systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? EditorTheme.timelineSelection : EditorTheme.dimText)
            .frame(width: VideoStudioMetrics.gutterIconSize, height: VideoStudioMetrics.gutterIconSize)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? EditorTheme.timelineSelection.opacity(0.14) : .clear)
            )
            .frame(width: VideoStudioMetrics.gutterWidth)
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
}
