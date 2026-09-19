import SwiftUI

/// Whether a tier-D tool should draw its chrome at tablet size.
///
/// Measured on the **window**, not on `horizontalSizeClass`. iPadOS reports
/// `.regular` from about 678pt, and the tools' structural switches — the
/// editor's sidebar, Collage's inspector, the Video Studio's rail — all use a
/// 700pt floor. A screen that sizes its buttons off the size class and its
/// layout off the measured width disagrees with itself in the band between
/// the two: 44pt buttons and an uncapped canvas drawn inside a layout that is
/// still the phone's.
///
/// `DESIGN.md` §"Chrome tầng D phải nở ở regular width" is the rule; this is
/// the one place the answer comes from.
private struct ToolRegularChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usesRegularToolChrome: Bool {
        get { self[ToolRegularChromeKey.self] }
        set { self[ToolRegularChromeKey.self] = newValue }
    }
}
