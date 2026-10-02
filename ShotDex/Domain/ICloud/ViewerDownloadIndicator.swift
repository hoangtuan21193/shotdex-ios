import Foundation

/// Where the viewer shows an iCloud download (FS-02.06 §4, AC-2). With the
/// chrome up it is the info panel's ring. Zoomed in, the chrome is hidden
/// (FS-02.01 §3) — and zooming is exactly what downloads the original — so
/// the ring alone stands in the photo's top-right corner until the
/// original arrives, or turns into the stall glyph.
enum ViewerDownloadIndicator: Equatable {
    case none
    /// Inside the info panel, with the rest of the chrome.
    case panel
    /// The 22 pt ring by itself in the top-right corner of the photo.
    case cornerRing
    /// The orange stall glyph by itself in the same corner.
    case cornerStall

    static func placement(isChromeVisible: Bool, isZoomed: Bool, isDownloading: Bool, isStalled: Bool) -> Self {
        guard isDownloading || isStalled else { return .none }
        if isChromeVisible { return .panel }
        guard isZoomed else { return .none }
        return isStalled ? .cornerStall : .cornerRing
    }
}
