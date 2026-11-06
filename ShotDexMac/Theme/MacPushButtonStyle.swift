import SwiftUI

/// Push button 28, radius 8 (DESIGN.md §10b): `accentFill` for the default,
/// `fill` for the others — whatever the system accent. Shared by the first
/// run and the sheets.
struct MacPushButtonStyle: ButtonStyle {
    let isDefault: Bool
    /// The default button's weight: 600 on the first run, 500 in sheets (boards).
    var defaultWeight: Font.Weight = .semibold

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isDefault: isDefault, defaultWeight: defaultWeight)
    }

    /// A view, so it can read focus and enabled state: keyboard navigation
    /// gets a ring, a disabled button looks it.
    private struct StyledLabel: View {
        let configuration: Configuration
        let isDefault: Bool
        let defaultWeight: Font.Weight
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.accent, lineWidth: isFocused ? 2 : 0))
                .opacity(isEnabled ? 1 : 0.4)
        }

        private var label: some View {
        configuration.label
            .font(.system(size: 13, weight: isDefault ? defaultWeight : .regular))
            .foregroundStyle(isDefault ? MacTheme.onAccentFill : Color.primary)
            .frame(minHeight: 28)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(isDefault ? MacTheme.accentFill : MacTheme.fill))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
