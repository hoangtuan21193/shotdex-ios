import SwiftUI

/// Paper-side colours for the collage — the neutrals that live *on the white
/// canvas of the collage frame itself*, not on the tier-D chrome.
///
/// DESIGN.md §14 draws the line explicitly: the empty-slot paper (`#EDE9E1`),
/// its inner border (`#B5AD9E`), the `Add photo` ink (`#6F6A60`) and the
/// Polaroid caption ink (`#4A443C`) are content colours over white, so they get
/// their own token group here rather than being smuggled into `EditorTheme`,
/// whose palette is the dark chrome. The chrome tokens (panel, accent, dividers)
/// stay in `EditorTheme`; geometry/radii/spacing stay in `AppTheme`.
enum CollageTheme {
    /// Empty-slot paper fill.
    static let slotPaper = Color(red: 0xED / 255, green: 0xE9 / 255, blue: 0xE1 / 255)
    /// Inner hairline drawn 1.5pt inside an empty slot.
    static let slotBorder = Color(red: 0xB5 / 255, green: 0xAD / 255, blue: 0x9E / 255)
    /// `+` glyph and `Add photo` label ink on the paper.
    static let slotInk = Color(red: 0x6F / 255, green: 0x6A / 255, blue: 0x60 / 255)
    /// Polaroid caption ink (serif), sitting under a photo on its white plate.
    static let captionInk = Color(red: 0x4A / 255, green: 0x44 / 255, blue: 0x3C / 255)
    /// Placeholder ink for a Polaroid plate that has no caption yet.
    static let captionPlaceholder = Color(red: 0xA9 / 255, green: 0xA2 / 255, blue: 0x96 / 255)
}
