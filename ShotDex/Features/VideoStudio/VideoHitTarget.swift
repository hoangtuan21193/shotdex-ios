import SwiftUI

extension View {
    /// Grows a control's **hit shape** to Apple's 44pt minimum without
    /// changing what is drawn, for the desk layout's short bands.
    ///
    /// `DESIGN.md` §"Chrome tầng D": a 28pt chip stays 28pt and gets a 44pt
    /// target by padding, reshaping and un-padding — the same trick the
    /// collage counter uses. The desk bands are 32 and 44 tall and their
    /// glyphs are smaller still, so every one of them needs it; the callers
    /// set a 44pt **width** directly, because a width that overlaps its
    /// neighbour's shape trades one missed tap for another.
    func videoHitTarget(drawnHeight: CGFloat) -> some View {
        let grow = max(0, (AppTheme.Size.minTouch - drawnHeight) / 2)
        return padding(.vertical, grow)
            .contentShape(Rectangle())
            .padding(.vertical, -grow)
    }
}
