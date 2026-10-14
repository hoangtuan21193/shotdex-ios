import CoreGraphics
import Foundation

/// Where the two subtitles go (FS-23.03 §2 Position, §4). Placed in the
/// part of the movie frame that is on screen — Fit: the letterboxed frame;
/// Fill: what the screen crops it to — never over each other, and lifted
/// above the transport glass while the chrome shows.
enum DualSubtitlePosition: String, CaseIterable, Codable, Sendable {
    case primaryBottomSecondaryTop
    /// The default.
    case bothBottomSecondaryAbove
    case bothBottomSecondaryBelow
}

enum DualSubtitleLayout {
    /// Between the two subtitles, and between them and the chrome.
    static let gap: CGFloat = 8
    /// From the frame's top and bottom edge, as a share of its height.
    static let edgeInset: CGFloat = 0.04
    /// Widest a subtitle line runs, as a share of the frame width.
    static let maxWidthShare: CGFloat = 0.9

    /// Point size at `scale` 1.0 = 100 %: 5 % of the frame height.
    static func fontSize(frameHeight: CGFloat, scale: Double) -> CGFloat {
        frameHeight * 0.05 * CGFloat(scale)
    }

    static func maxWidth(frame: CGRect, bounds: CGRect) -> CGFloat {
        area(frame: frame, bounds: bounds).width * maxWidthShare
    }

    struct Block: Equatable, Sendable {
        /// Measured by the view at `maxWidth`.
        var size: CGSize
        /// The cue asks for the top (ASS `\an8`, WebVTT `line:0`).
        var wantsTop = false
    }

    struct Placement: Equatable, Sendable {
        var primary: CGRect?
        var secondary: CGRect?
    }

    /// - Parameters:
    ///   - frame: the movie frame in view coordinates (Fill: larger than
    ///     `bounds`).
    ///   - bounds: the view.
    ///   - chromeTop: the top edge of the transport glass while it shows.
    ///   - chromeBottom: the bottom edge of the top bar (✕, title) while
    ///     it shows — a subtitle at the top goes below it.
    static func place(
        primary: Block?, secondary: Block?, position: DualSubtitlePosition,
        frame: CGRect, bounds: CGRect, chromeTop: CGFloat? = nil, chromeBottom: CGFloat? = nil
    ) -> Placement {
        let area = area(frame: frame, bounds: bounds)
        let inset = area.height * edgeInset
        var floor = area.maxY - inset
        if let chromeTop { floor = min(floor, chromeTop - gap) }
        var ceiling = area.minY + inset
        if let chromeBottom { ceiling = max(ceiling, chromeBottom + gap) }

        // Which block goes to the top region, which to the bottom stack.
        var top: [(Bool, Block)] = []  // (isPrimary, block), first = highest
        var bottom: [(Bool, Block)] = []  // first = lowest
        let secondaryOnTop = position == .primaryBottomSecondaryTop
        if let primary {
            if primary.wantsTop { top.append((true, primary)) } else { bottom.append((true, primary)) }
        }
        if let secondary {
            if secondary.wantsTop || secondaryOnTop {
                top.append((false, secondary))
            } else if position == .bothBottomSecondaryBelow {
                bottom.insert((false, secondary), at: 0)
            } else {
                bottom.append((false, secondary))
            }
        }

        var result = Placement()
        func put(_ isPrimary: Bool, _ rect: CGRect) {
            if isPrimary { result.primary = rect } else { result.secondary = rect }
        }
        func rect(_ block: Block, minY: CGFloat) -> CGRect {
            let width = min(block.size.width, area.width * maxWidthShare)
            return CGRect(x: area.midX - width / 2, y: minY, width: width, height: block.size.height)
        }

        var y = floor
        var lowestTop = ceiling
        for (isPrimary, block) in bottom {
            y -= block.size.height
            put(isPrimary, rect(block, minY: y))
            y -= gap
        }
        let bottomTop = y + gap
        var cursor = ceiling
        for (isPrimary, block) in top {
            put(isPrimary, rect(block, minY: cursor))
            cursor += block.size.height + gap
            lowestTop = cursor - gap
        }
        // A short frame with two top lines and two bottom lines: the top
        // stack gives way upwards rather than covering the bottom one.
        if !top.isEmpty, !bottom.isEmpty, lowestTop + gap > bottomTop {
            let shift = lowestTop + gap - bottomTop
            if let primary = result.primary, top.contains(where: { $0.0 }) { result.primary = primary.offsetBy(dx: 0, dy: -shift) }
            if let secondary = result.secondary, top.contains(where: { !$0.0 }) { result.secondary = secondary.offsetBy(dx: 0, dy: -shift) }
        }
        return result
    }

    /// The part of the frame the viewer sees.
    static func area(frame: CGRect, bounds: CGRect) -> CGRect {
        let visible = frame.intersection(bounds)
        return visible.isNull ? bounds : visible
    }
}
