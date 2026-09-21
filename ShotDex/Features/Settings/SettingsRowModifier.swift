import SwiftUI

extension View {
    /// Marks a Settings row as the thing its `SettingsRowLabel` names.
    ///
    /// Three jobs, all about finding the row again: an `id` a `ScrollViewReader`
    /// can scroll to when a search result sends the reader here, the brief
    /// highlight that says *this is the one*, and a stable accessibility
    /// identifier for the UI driver. The identifier is warranted by the same
    /// rule the Video Studio's four follow — a bare label is ambiguous here,
    /// because "Support" is at once a row, a sidebar item and a pane title, and
    /// "Open Settings" is two different rows. It carries a `.flashing` suffix
    /// while the row is lit, which turns "did the highlight happen" from a
    /// judgement about a screenshot into a line in an element dump.
    func settingsRow(_ label: SettingsRowLabel) -> some View {
        modifier(SettingsRowMarker(label: label))
    }
}

private struct SettingsRowMarker: ViewModifier {
    @Environment(SettingsNavigation.self) private var navigation

    let label: SettingsRowLabel

    func body(content: Content) -> some View {
        let isFlashing = navigation.flashedRow == label
        content
            .id(label)
            // `nil`, not `.clear`: a clear row background replaces the grouped
            // list's own fill and leaves the row floating on the grey.
            .listRowBackground(isFlashing ? Color.accentColor.opacity(0.18) : nil)
            .animation(AppTheme.Motion.standard, value: isFlashing)
            .accessibilityIdentifier(
                isFlashing
                    ? "settings.row.\(label.rawValue).flashing"
                    : "settings.row.\(label.rawValue)"
            )
    }
}
