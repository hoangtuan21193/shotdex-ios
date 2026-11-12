import SwiftUI

extension View {
    /// Grows a control's **hit shape** to Apple's 44pt minimum without
    /// changing what is drawn.
    ///
    /// `DESIGN.md` §"Chrome tầng D": a 28–32pt tier-D chip or pill keeps its
    /// look and gets a 44pt target by padding, reshaping and un-padding
    /// (DUO_LOOP 22b — one rule for the editor, the Video Studio and the
    /// collage, not a Duo special case). Vertical only: a width that
    /// overlaps its neighbour's shape trades one missed tap for another, so
    /// narrow controls set their width themselves.
    func minimumHitTarget(drawnHeight: CGFloat) -> some View {
        let grow = max(0, (AppTheme.Size.minTouch - drawnHeight) / 2)
        return padding(.vertical, grow)
            .contentShape(Rectangle())
            .padding(.vertical, -grow)
    }
}
