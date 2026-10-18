import SwiftUI

/// The Mac's design tokens (DESIGN.md §10b, K4). The accent is ShotDex amber
/// on every Mac, whatever the system accent says (FS-18 AC-12).
enum MacTheme {
    static let accent = Color(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255)
}
