import SwiftUI

/// Where the player's stage goes (FS-23.02 §4). On a phone held upright with
/// a wide movie, the whole stage — picture, taps and chrome — turns 90° inside
/// the interface, like the Photos video viewer (FS-02.02 §8): no rotation API,
/// so Rotation Lock keeps working. The iPad and the Duo's inner screen fill
/// the window as it is.
struct MoviePlayerLayout: Equatable {
    /// The stage before any turn: landscape when rotated.
    let stageSize: CGSize
    let isRotated: Bool
    /// From the stage edges to the chrome.
    let chromeInsets: EdgeInsets

    init(size: CGSize, safeArea: EdgeInsets, isCompactWidth: Bool, isLandscapePicture: Bool) {
        isRotated = isCompactWidth && isLandscapePicture && size.height > size.width
        if isRotated {
            stageSize = CGSize(width: size.height, height: size.width)
            // Turned clockwise: the island's edge becomes the leading one.
            // Both sides take the larger inset so the title stays centred
            // (board PH_MoviePlayer: 62 on an iPhone 17).
            let side = max(safeArea.top, safeArea.bottom)
            // The screen's trailing edge is the stage's top, its leading edge
            // the stage's bottom — the Duo cover's 84 pt rail lands on top.
            chromeInsets = EdgeInsets(
                top: max(AppTheme.Spacing.lg, safeArea.trailing), leading: side,
                bottom: max(AppTheme.Spacing.xl, safeArea.leading), trailing: side
            )
        } else {
            stageSize = size
            // With the status bar hidden an iPad reports no top inset;
            // the display's rounded corner still needs clearing.
            chromeInsets = EdgeInsets(
                top: max(safeArea.top, AppTheme.Spacing.lg) + AppTheme.Spacing.sm,
                leading: safeArea.leading + AppTheme.Spacing.lg,
                bottom: safeArea.bottom + AppTheme.Spacing.sm,
                trailing: safeArea.trailing + AppTheme.Spacing.lg
            )
        }
    }
}
