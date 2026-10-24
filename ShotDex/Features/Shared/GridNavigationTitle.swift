import SwiftUI

/// A grid screen's name with the date of what is on screen under it, for the
/// navigation bar's principal slot. The grid draws no date headers, so this
/// is where "when am I" lives.
///
/// Leading-aligned and stretched across the slot: centred, the block's width
/// followed the date's ("May 3" vs "September 23"), so both lines slid left
/// and right on every scroll.
struct GridNavigationTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.18), value: subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    /// The window is the Duo's inner display (`VideoStudioWindowClass.duoInner`),
    /// set once at the root by `resolvesDuoInner()`.
    @Entry var isDuoInner = false
}

extension View {
    /// Works out once, for every screen below, whether the window is the
    /// Duo's inner display.
    func resolvesDuoInner() -> some View {
        modifier(DuoInnerResolver())
    }
}

private struct DuoInnerResolver: ViewModifier {
    @State private var isDuoInner = false

    func body(content: Content) -> some View {
        content
            .environment(\.isDuoInner, isDuoInner)
            .onGeometryChange(for: Bool.self) { proxy in
                let insets = proxy.safeAreaInsets
                let window = VideoStudioWindowClass.windowSize(
                    content: proxy.size,
                    top: insets.top,
                    bottom: insets.bottom,
                    leading: insets.leading,
                    trailing: insets.trailing
                )
                return VideoStudioWindowClass.resolve(window: window, trailingInset: insets.trailing) == .duoInner
            } action: { isDuoInner = $0 }
    }
}

/// A grid screen's Select button. Spelled out, like Photos — except on the
/// Duo's inner display, whose vertical toolbar takes icon items only: a word
/// stays behind in the horizontal row on its own (DUO_LOOP row 1a).
struct SelectPhotosButton: View {
    @Environment(\.isDuoInner) private var isDuoInner
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isDuoInner {
                Label("Select", systemImage: "checkmark.circle")
            } else {
                Text("Select")
            }
        }
        .tint(.primary)
        .accessibilityLabel("Select photos")
    }
}
