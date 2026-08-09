import SwiftUI

extension View {
    /// Liquid Glass on iOS 26; a blurred material with a hairline edge and drop
    /// shadow on earlier tiers. One of the three glass entrypoints (DESIGN.md §9)
    /// — the flexible one for an arbitrary shape (capsule, circle, rounded rect)
    /// when `GlassPanel`/`GlassIconButton` don't fit. Never write
    /// `.background(.ultraThinMaterial, in:)` directly in a feature file.
    @ViewBuilder
    func glassBackground(_ shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        }
    }
}
