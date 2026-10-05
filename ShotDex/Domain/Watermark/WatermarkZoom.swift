import CoreGraphics
import Foundation

/// Zoom on the Watermark screen's preview (FS-05.04 §4a): Fit · 200% ·
/// 400%, a percentage of the fitted preview — the way the editor's zoom pill
/// counts (`EditorLayoutMetrics.zoomPercent`).
enum WatermarkZoom: CaseIterable, Hashable, Sendable {
    case fit
    case double
    case quadruple

    var scale: CGFloat {
        switch self {
        case .fit: 1
        case .double: 2
        case .quadruple: 4
        }
    }

    /// The capsule's word: `Fit`, `200%`, `400%`.
    var title: String {
        switch self {
        case .fit: WatermarkCopy.fit()
        case .double, .quadruple: "\(Int(scale * 100))%"
        }
    }

    /// The longest edge a zoomed page is re-read at: never more than the
    /// file being written, never more than the screen can show at this
    /// level, never more than 4096 px.
    static let detailCap: CGFloat = 4_096

    static func detailLongEdge(exportSize: CGSize, displaySize: CGSize, scale: CGFloat, screenScale: CGFloat) -> CGFloat {
        let export = max(exportSize.width, exportSize.height)
        let shown = max(displaySize.width, displaySize.height) * scale * screenScale
        return max(1, min(export, shown, detailCap)).rounded()
    }

    /// Where the zoomed picture sits, as an offset from the view's centre:
    /// the stamp's centre (`focus`, in the fitted view's points, top-left
    /// origin) brought to the middle, plus the finger's `pan`, then clamped
    /// so the picture still covers the frame on every side it can.
    static func offset(
        focus: CGPoint?,
        pan: CGSize = .zero,
        imageSize: CGSize,
        displaySize: CGSize,
        scale: CGFloat,
        clamps: Bool = true
    ) -> CGSize {
        guard scale > 1, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fit = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        let centre = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
        let target = focus ?? centre
        let wanted = CGSize(
            width: -(target.x - centre.x) * scale + pan.width,
            height: -(target.y - centre.y) * scale + pan.height
        )
        guard clamps else { return wanted }
        let zoomed = CGSize(width: fitted.width * scale, height: fitted.height * scale)
        let reach = CGSize(
            width: max(0, (zoomed.width - displaySize.width) / 2),
            height: max(0, (zoomed.height - displaySize.height) / 2)
        )
        return CGSize(
            width: min(reach.width, max(-reach.width, wanted.width)),
            height: min(reach.height, max(-reach.height, wanted.height))
        )
    }
}
