import SwiftUI

/// Round material-blurred icon button used in the floating chrome
/// (e.g. the search button next to the tab pill).
struct GlassIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    /// Glyph tint (e.g. `.red` for destructive). Dimmed when disabled.
    var tint: Color = Color(.label)
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var glyph: some View {
        let base = Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(isEnabled ? tint : Color(.tertiaryLabel))
            .frame(width: 52, height: 52)
            .contentShape(Circle())

        if #available(iOS 26.0, *) {
            // Real Liquid Glass, matching the native toolbar buttons.
            base.glassEffect(.regular.interactive(), in: .circle)
        } else {
            base
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GlassIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", action: {})
    }
}
