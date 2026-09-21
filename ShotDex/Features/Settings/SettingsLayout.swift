import SwiftUI

/// Which container the Settings screen builds itself out of, and what happens
/// to the reader's place when the window changes size class underneath them.
///
/// Every answer here is a pure function of its arguments, for two reasons.
/// The first is proof: four window sizes cannot be built inside a unit test,
/// a function can. The second is the kill switch — `usesSplitView` returning
/// `false` puts every device back on the single-column list this screen shipped
/// with, without touching a view, which is the first thing to try if the split
/// layout misbehaves in the field.
///
/// The threshold is the **size class**, not a point count. The standard being
/// matched is Settings on iPadOS, which is already two columns on an iPad 11"
/// in portrait (834pt) — a 900pt rule would leave exactly that device on the
/// phone layout. See `DESIGN.md` §10.1f and `docs/02-functional-spec/FS-08-settings.md`.
enum SettingsLayout {

    /// `true` when Settings should be a `NavigationSplitView`.
    ///
    /// `nil` — the size class before SwiftUI has resolved one — falls to the
    /// single column: the list is correct at every width, the split view is
    /// not, so the unknown case takes the layout that cannot be wrong.
    static func usesSplitView(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular
    }

    /// The sidebar item to select when a narrow window becomes wide.
    ///
    /// Whatever the reader had pushed is what they were reading, so it becomes
    /// the selection; an empty stack means they were on the list itself and
    /// land on the first item.
    static func selection(afterExpanding path: [SettingsSection]) -> SettingsSection {
        path.last ?? .photoLibrary
    }

    /// The navigation stack to restore when a wide window becomes narrow.
    ///
    /// The selected item becomes the pushed screen — except for the first item,
    /// which stays unpushed. In the split view something must always be
    /// selected, so `.photoLibrary` is as much "nothing chosen yet" as it is a
    /// choice; pushing it would make the reader tap Back to reach the settings
    /// list they never left.
    static func path(afterCollapsing selection: SettingsSection?) -> [SettingsSection] {
        guard let selection, selection != .photoLibrary else { return [] }
        return [selection]
    }
}
