import SwiftUI

/// The timeline's lane geometry for the window it is drawn in.
///
/// It travels in the environment rather than as a parameter because every
/// level of the timeline needs it — the ruler, the gutter, each lane, each
/// clip cell, the transition chips — and threading one struct through five
/// initialisers to reach a chip is how the phone sizes got hard-coded in the
/// first place.
private struct VideoLaneMetricsKey: EnvironmentKey {
    static let defaultValue = VideoStudioMetrics.Lanes.duo
}

extension EnvironmentValues {
    var videoLaneMetrics: VideoStudioMetrics.Lanes {
        get { self[VideoLaneMetricsKey.self] }
        set { self[VideoLaneMetricsKey.self] = newValue }
    }
}

/// The window class the studio is laid out for, for the panels whose rows
/// differ on one device only — the Duo cover's Beats (FS-12.12 §3).
private struct VideoStudioWindowClassKey: EnvironmentKey {
    static let defaultValue: VideoStudioWindowClass? = nil
}

extension EnvironmentValues {
    var videoStudioWindowClass: VideoStudioWindowClass? {
        get { self[VideoStudioWindowClassKey.self] }
        set { self[VideoStudioWindowClassKey.self] = newValue }
    }
}
