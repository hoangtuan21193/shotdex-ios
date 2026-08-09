import SwiftUI

/// Geometry and motion tokens shared by all four surface tiers (DESIGN.md §3).
///
/// `AppTheme` holds no colour: tiers A/B/C get light/dark for free from system
/// colours, and tier D keeps its dark palette in `EditorTheme`. One source for
/// geometry, two tables for colour — never a second copy of either.
enum AppTheme {
    /// Corner-radius scale (DESIGN.md §5). Only these five values, always with
    /// `style: .continuous` — use `RoundedRectangle.app(_:)` to get both.
    enum Radius {
        /// 8 — chip, badge, small thumbnail, rule-row input.
        static let sm: CGFloat = 8
        /// 12 — card, preset chip, custom list row, large button.
        static let md: CGFloat = 12
        /// 16 — section/panel, preview frame, chart card.
        static let lg: CGFloat = 16
        /// 22 — floating glass bar (selection bar, action bar).
        static let xl: CGFloat = 22
        /// 28 — large glass panel (metadata panel, glass sheet).
        static let xxl: CGFloat = 28
    }

    /// Spacing scale (DESIGN.md §6): 4 / 8 / 12 / 16 / 20 / 24. Never 6/10/14/18.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    /// Fixed sizes (DESIGN.md §6).
    enum Size {
        /// Horizontal screen margin for tiers A/B and tier-D panels.
        static let screenMargin: CGFloat = 16
        /// Horizontal margin for floating tier-C chrome.
        static let floatingChromeMargin: CGFloat = 20
        /// Minimum hit target.
        static let minTouch: CGFloat = 44
        /// Round glass button (`GlassIconButton`).
        static let glassButton: CGFloat = 52
        /// Icon button inside a dark action bar (capsule padding 4 around it).
        static let darkActionIcon: CGFloat = 40
        /// Full-width primary action button height (pairs with `Radius.md`).
        static let primaryActionHeight: CGFloat = 50
        /// Pill / token height in tier D (`EditorPillLabel`).
        static let pillHeightDark: CGFloat = 28
        /// Pill / token height in tiers A/B.
        static let pillHeightLight: CGFloat = 32
        /// Segmented control height (container radius `Radius.sm` + 2).
        static let segmentedHeight: CGFloat = 32
    }

    /// Motion tokens (DESIGN.md §11). No view writes its own duration.
    enum Motion {
        /// State changes.
        static let standard = Animation.easeOut(duration: 0.22)
        /// Sliding panels.
        static let panelSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)
    }
}

extension RoundedRectangle {
    /// Continuous rounded rectangle at an `AppTheme.Radius` value — the only way a
    /// rounded rect should be built in the app (DESIGN.md §5 requires `.continuous`).
    static func app(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
