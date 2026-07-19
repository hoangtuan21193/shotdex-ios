import SwiftUI

/// Curated series colors for Swift Charts — replaces the framework default
/// palette. Ordered so adjacent series stay distinguishable, and every color
/// is a system color, so light/dark variants come for free.
enum ChartPalette {
    static let colors: [Color] = [
        .indigo,
        .teal,
        .orange,
        .pink,
        .mint,
        .purple,
        .yellow,
        .cyan,
    ]

    /// Single-series bar fill: subtle vertical fade of the lead color.
    static let bar = LinearGradient(
        colors: [Color.indigo, Color.indigo.opacity(0.65)],
        startPoint: .top,
        endPoint: .bottom
    )
}
