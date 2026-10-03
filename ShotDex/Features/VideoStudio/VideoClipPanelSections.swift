import Foundation

/// What a selected clip's panel shows under its command row, in order
/// (FS-12.04b §6, FS-12.05 §3).
///
/// A video has **no Duration**: its length is cut with the edge handles or
/// Trim → Start/End to Playhead, and a third way to cut — a slider that
/// trims the tail — was one too many. A still has nothing else that sets
/// its length, so it keeps Duration.
enum VideoClipPanelSection: Equatable, CaseIterable {
    case speed, volume, duration, fade, motion
}

enum VideoClipPanelSections {
    static func sections(for kind: VideoClipKind) -> [VideoClipPanelSection] {
        switch kind {
        case .video: [.speed, .volume, .fade, .motion]
        case .photo, .freeze: [.duration, .fade, .motion]
        }
    }

    /// The Speed chips (FS-12.04b §6).
    static let speedPresets: [Double] = [0.5, 1, 2, 4]
}
