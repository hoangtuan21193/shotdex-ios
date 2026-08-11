import CoreGraphics

/// Fixed geometry for the Turn-2 Video Studio, in points on the 393×852
/// reference frame (Dynamic Island). The screen is a vertical stack of fixed
/// bands; only the preview flexes. Everything here is read by the screen, the
/// timeline, and the inspector so no view invents its own measurement.
///
/// Vertical map (spec §1):
///   band 37 @ y11 · preview 221 · transport 44 · timeline 248 · panel 260.
enum VideoStudioMetrics {
    // MARK: Screen bands

    static let commandBandHeight: CGFloat = 37
    static let previewHeight: CGFloat = 221
    static let transportHeight: CGFloat = 44
    static let timelineHeight: CGFloat = 248
    static let panelHeight: CGFloat = 260

    // MARK: Panel tiers (sum = 260)

    static let panelTitleHeight: CGFloat = 36
    static let panelParamHeight: CGFloat = 102
    static let panelCommandHeight: CGFloat = 62
    static let panelExportHeight: CGFloat = 50
    static let panelSafeAreaInset: CGFloat = 10

    // MARK: Timeline verticals (sum = 248)

    static let timelineTopPadding: CGFloat = 8
    static let rulerHeight: CGFloat = 26
    static let rulerToTracks: CGFloat = 3
    static let trackSpacing: CGFloat = 3
    static let scrollbarHeight: CGFloat = 3
    static let timelineBottomPadding: CGFloat = 5

    /// Track order top-to-bottom and their heights (spec §4.2 / §4.4).
    enum Track: Int, CaseIterable {
        case text, video, filter, music

        var height: CGFloat {
            switch self {
            case .text: 40
            case .video: 66
            case .filter: 40
            case .music: 48
            }
        }

        var systemImage: String {
            switch self {
            case .text: "textformat"
            case .video: "film"
            case .filter: "camera.filters"  // two intersecting circles
            case .music: "music.note"
            }
        }
    }

    /// Y of a track's top edge from the timeline's top.
    static func trackTop(_ track: Track) -> CGFloat {
        var y = timelineTopPadding + rulerHeight + rulerToTracks
        for candidate in Track.allCases {
            if candidate == track { return y }
            y += candidate.height + trackSpacing
        }
        return y
    }

    /// Bottom edge of the last track (where the scrollbar rides).
    static var trackAreaBottom: CGFloat {
        trackTop(.music) + Track.music.height
    }

    // MARK: Timeline horizontals

    /// The fixed left icon column; the scrolling content starts after it.
    static let gutterWidth: CGFloat = 38
    /// Playhead's absolute x on the 393-wide reference frame (spec §4.1).
    /// At runtime the screen recomputes it as `gutterWidth + rowAreaWidth / 2`.
    static let referencePlayheadX: CGFloat = 215.5

    /// x of the fixed playhead for a given screen width: centre of the row area.
    static func playheadX(screenWidth: CGFloat) -> CGFloat {
        gutterWidth + (screenWidth - gutterWidth) / 2
    }

    /// Half the row area — the content padding at each end so 0s and the last
    /// mark can both sit under the centred playhead.
    static func rowAreaHalfWidth(screenWidth: CGFloat) -> CGFloat {
        (screenWidth - gutterWidth) / 2
    }

    // MARK: Scale

    static let defaultPointsPerSecond: CGFloat = 55
    static let pointsPerSecondRange: ClosedRange<CGFloat> = 20...160

    // MARK: Bands & controls (timeline-only radius exception r-track = 6)

    static let trackRadius: CGFloat = 6
    static let commandCellRadius: CGFloat = 10
    static let exportPillRadius: CGFloat = 19

    static let clipCellHeight: CGFloat = 54
    static let chipBandHeight: CGFloat = 28
    static let musicBandHeight: CGFloat = 32
    /// Extended hit target for the 28pt chip bands (spec §8: ≥44).
    static let bandHitInset: CGFloat = -8

    static let gutterIconSize: CGFloat = 18
    static let commandCellWidth: CGFloat = 52
    static let commandCellHeight: CGFloat = 54
    static let inspectorTitleButton: CGFloat = 30
    static let addMediaButtonWidth: CGFloat = 40
    static let transitionChipSize: CGFloat = 22
}
