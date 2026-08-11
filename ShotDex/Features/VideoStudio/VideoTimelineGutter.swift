import SwiftUI

/// The fixed left icon column (spec §4.2): icon-only, no labels, no scroll. The
/// track holding the selected object lights up in timeline-blue.
struct VideoTimelineGutter: View {
    let activeTrack: VideoStudioMetrics.Track?

    var body: some View {
        ZStack(alignment: .topLeading) {
            EditorTheme.panelSolid
            ForEach(VideoStudioMetrics.Track.allCases, id: \.rawValue) { track in
                icon(track)
                    .offset(y: VideoStudioMetrics.trackTop(track))
            }
        }
        .frame(
            width: VideoStudioMetrics.gutterWidth,
            height: VideoStudioMetrics.timelineHeight,
            alignment: .topLeading
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(EditorTheme.hairline).frame(width: 1)
        }
    }

    private func icon(_ track: VideoStudioMetrics.Track) -> some View {
        let active = track == activeTrack
        return ZStack {
            if active { EditorTheme.timelineSelection.opacity(0.1) }
            Image(systemName: track.systemImage)
                .font(.system(size: VideoStudioMetrics.gutterIconSize, weight: .regular))
                .foregroundStyle(active ? EditorTheme.timelineSelection : Color.white.opacity(0.42))
        }
        .frame(width: VideoStudioMetrics.gutterWidth, height: track.height)
        .accessibilityLabel(name(track))
    }

    private func name(_ track: VideoStudioMetrics.Track) -> String {
        switch track {
        case .text: String(localized: "Text track")
        case .video: String(localized: "Video track")
        case .filter: String(localized: "Filter track")
        case .music: String(localized: "Music track")
        }
    }
}
