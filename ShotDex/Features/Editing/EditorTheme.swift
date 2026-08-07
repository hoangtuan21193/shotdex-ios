import SwiftUI

/// Design tokens for the photo editor. One accent colour, one panel colour, one
/// animation curve — every editor view reads them from here so the chrome stays
/// consistent between the panel, the on-image glass and the sheets.
enum EditorTheme {
    /// Follows the accent picked in Settings. Read from `UserDefaults` rather
    /// than the environment because these are static tokens; the editor is only
    /// ever built after Settings closes, so there is nothing to refresh.
    static var accent: Color { AppAccentTheme.stored.color }
    static let background = Color.black
    static let panel = Color(white: 0.055)
    /// The opaque "28c" panel slab (`#0f1012`) — no blur, no glass. The whole edit
    /// panel sits on this and the image never shows through it.
    static let panelSolid = Color(red: 15 / 255, green: 16 / 255, blue: 18 / 255)
    /// The 28c panel's 1pt top edge and its inner tier dividers.
    static let panelTopHairline = Color.white.opacity(0.10)
    static let panelDivider = Color.white.opacity(0.07)
    static let stickyHeader = Color(white: 0.078)
    static let control = Color(white: 0.11)
    static let sliderTrack = Color(white: 0.165)
    static let hairline = Color.white.opacity(0.09)
    static let secondaryText = Color.white.opacity(0.55)
    static let dimText = Color.white.opacity(0.35)
    static let clipping = Color(red: 1, green: 0.271, blue: 0.227)
    static let maskRow = Color(white: 0.102)
    static var activeRow: Color { accent.opacity(0.1) }
    static let glass = Color(white: 0.07).opacity(0.6)
    /// For glass that sits over the photo permanently — the histogram card —
    /// where the image underneath still has to stay legible.
    static let glassLight = Color(white: 0.05).opacity(0.12)
    static let glassStroke = Color.white.opacity(0.16)
    static let histogramRed = Color(red: 1, green: 0.271, blue: 0.227)
    static let histogramGreen = Color(red: 0.204, green: 0.78, blue: 0.349)
    /// Spelled out instead of tracking `accent`: the blue channel of an RGB
    /// histogram has to stay blue whatever the app's accent is.
    static let histogramBlue = Color(red: 0.039, green: 0.518, blue: 1)

    static let animation = Animation.easeOut(duration: 0.22)
    static let panelSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)

    static let panelTitle = Font.system(size: 19, weight: .semibold)
    static let groupLabel = Font.system(size: 11.5, weight: .bold)
    static let rowLabel = Font.system(size: 12)
    static let rowValue = Font.system(size: 11.5).monospacedDigit()
    static let tabLabel = Font.system(size: 10.5)
    static let pillLabel = Font.system(size: 11, weight: .semibold)
    static let maskTitle = Font.system(size: 14.5, weight: .semibold)
    static let maskSubtitle = Font.system(size: 11.5)

    /// Temp and Tint get a coloured trough instead of the grey one, so the
    /// direction of the correction is readable without moving the knob.
    static func troughGradient(for kind: PhotoAdjustmentKind) -> LinearGradient? {
        switch kind {
        case .warmth, .rawTemperature:
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.55, blue: 1), Color(red: 1, green: 0.6, blue: 0.2)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .tint, .rawTint:
            LinearGradient(
                colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.72, green: 0.36, blue: 1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            nil
        }
    }
}

/// Blurred dark glass used by every on-image control.
struct EditorGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    var tint: Color = EditorTheme.glass
    /// How much of the blur to keep. The histogram card turns this down so the
    /// photo reads through it; chrome that carries text keeps it at full strength.
    var materialOpacity: Double = 1

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial.opacity(materialOpacity),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(EditorTheme.glassStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    }
}

extension View {
    func editorGlass(
        cornerRadius: CGFloat = 14,
        tint: Color = EditorTheme.glass,
        materialOpacity: Double = 1
    ) -> some View {
        modifier(
            EditorGlassBackground(
                cornerRadius: cornerRadius,
                tint: tint,
                materialOpacity: materialOpacity
            )
        )
    }
}

/// Small pill used for on-image affordances (`HOLD · BEFORE`, `1:1`, mask
/// overlay). An optional symbol carries state the words alone would not: an eye
/// with a slash says the red mask overlay is hidden.
struct EditorPillLabel: View {
    /// Nil for an icon-only pill, used where the row would otherwise not fit.
    let text: String?
    var systemImage: String?
    var isActive = false
    /// Glyph colour override for icons that *are* a colour — the mask overlay
    /// pill shows the red it switches on. Nil keeps the active/secondary pair.
    var iconColor: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                // An icon standing alone is the whole label, so it gets the extra
                // point size a caption-height glyph next to text does not need.
                Image(systemName: systemImage)
                    .font(.system(size: text == nil ? 13 : 11, weight: .semibold))
                    .foregroundStyle(
                        iconColor
                            ?? (isActive ? Color.white : EditorTheme.secondaryText)
                    )
            }
            if let text {
                Text(text)
                    .font(EditorTheme.pillLabel)
                    .tracking(0.8)
                    .lineLimit(1)
            }
        }
            // A pill whose label truncates is worse than one that overflows: it
            // keeps its natural width and the row around it has to make room.
            .fixedSize()
            .foregroundStyle(isActive ? Color.white : EditorTheme.secondaryText)
            // Icon-only pills run seven abreast in the mask action row; two
            // points of padding each is what lets a 375pt screen seat them all.
            .padding(.horizontal, text == nil ? 8 : 10)
            .frame(height: 28)
            .background(
                isActive ? EditorTheme.accent : Color.clear,
                in: Capsule()
            )
            .editorGlass(cornerRadius: 14)
    }
}
