import CoreGraphics

/// Which of the Video Studio's five layouts a window gets (FS-12.03 §1,
/// FS-12.07b §1). Chosen by the **window** — its size and the inset the
/// system keeps on its trailing edge — never by the device's name, so an
/// iPad in Slide Over gets the phone layout and a Stage Manager window that
/// is wide but short gets the Duo's inner one.
///
/// One classifier for every layout decision in the studio; no screen writes
/// its own width test.
enum VideoStudioWindowClass: CaseIterable, Equatable, Sendable {
    /// Compact, no trailing rail: an iPhone (FS-12.07), or any narrow window.
    case phone
    /// Compact with an 84pt trailing rail: the Duo's cover display (FS-12.07b).
    case duoCover
    /// Wide but short: the Duo's inner display (FS-12.03 §4).
    case duoInner
    /// Wide, not short, wider than tall: the three-column desk (FS-12.03 §2).
    case iPadLandscape
    /// Wide, not short, at least as tall as wide: the dock (FS-12.03 §3).
    case iPadPortrait

    /// Narrower than this is compact.
    static let wideWindowWidth: CGFloat = 600
    /// A compact window with at least this much on its trailing edge is the
    /// Duo's cover: the system keeps that strip for its rail.
    static let coverRailInset: CGFloat = 84
    /// Shorter than this is a short window (NF-05 §4).
    static let shortWindowHeight: CGFloat = 720

    static func resolve(window: CGSize, trailingInset: CGFloat) -> VideoStudioWindowClass {
        guard window.width >= wideWindowWidth else {
            return trailingInset >= coverRailInset ? .duoCover : .phone
        }
        if isShortWindow(height: window.height) { return .duoInner }
        return window.width > window.height ? .iPadLandscape : .iPadPortrait
    }

    /// The window is short (NF-05 §4): a layout budgeted for a tall phone or
    /// a deep iPad does not fit, whatever the width.
    static func isShortWindow(height: CGFloat) -> Bool {
        height < shortWindowHeight
    }

    var isCompact: Bool { self == .phone || self == .duoCover }
}
