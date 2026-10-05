import Foundation
import ShotDexKit

/// The words of FS-05.04. Every string lives in the `Watermark` string table
/// (`Resources/Watermark.xcstrings`); counts go through its plural variants.
/// One name, **Watermark**, on every form, in Settings and in the share sheet.
enum WatermarkCopy {
    static let table = "Watermark"

    static func watermark(locale: Locale = .current) -> String {
        String(localized: "Watermark", table: table, locale: locale, comment: "Export form row and screen title: the stamp added on export")
    }

    /// Resize summary: photos that went without the stamp because every token
    /// came out empty (FS-05.04 §5).
    static func savedWithoutWatermark(_ count: Int, locale: Locale = .current) -> String {
        String(localized: "\(count) photos saved without the watermark", table: table, locale: locale, comment: "Resize summary: photos with nothing to stamp (plural)")
    }

    /// Summary and share-sheet note: photos whose edit already carried a layer
    /// pasted from the preset, so they were not stamped twice.
    static func alreadyHadWatermark(_ count: Int, locale: Locale = .current) -> String {
        String(localized: "\(count) photos already had this watermark", table: table, locale: locale, comment: "Export summary: photos whose edit already had this watermark, not stamped twice (plural)")
    }

    /// The reason beside each of those photos.
    static func nothingToStamp(preset: String, locale: Locale = .current) -> String {
        String(localized: "Every part of \(preset) is empty for this photo.", table: table, locale: locale, comment: "Resize summary: why a photo has no watermark — its tokens all came out empty")
    }

    static func withoutWatermarkSection(locale: Locale = .current) -> String {
        String(localized: "Without Watermark", table: table, locale: locale, comment: "Resize summary section: photos that went without the watermark")
    }

    // MARK: Form row (FS-05.04 §4)

    /// The Resize form, as the Watermark screen's back button names it.
    static func resizeForm(locale: Locale = .current) -> String {
        String(localized: "Resize", table: table, locale: locale, comment: "The form the Watermark screen goes back to")
    }

    /// The row's value when the watermark is off, or its preset is gone.
    static func off(locale: Locale = .current) -> String {
        String(localized: "Off", table: table, locale: locale, comment: "Watermark row value: no watermark")
    }

    /// The row's value before any preset exists.
    static func none(locale: Locale = .current) -> String {
        String(localized: "None", table: table, locale: locale, comment: "Watermark row value: no watermark preset saved yet")
    }

    /// Resize's Delete Originals line while a watermark is on.
    static func originalsAreKept(locale: Locale = .current) -> String {
        String(localized: "Originals are kept when you add a watermark.", table: table, locale: locale, comment: "Resize: why Delete Originals is off while a watermark is on")
    }

    // MARK: Watermark screen

    static func addWatermark(locale: Locale = .current) -> String {
        String(localized: "Add Watermark", table: table, locale: locale, comment: "Watermark screen switch")
    }

    static func done(locale: Locale = .current) -> String {
        String(localized: "Done", table: table, locale: locale, comment: "Watermark screen: close")
    }

    static func position(locale: Locale = .current) -> String {
        String(localized: "Position", table: table, locale: locale, comment: "Watermark screen: the 3×3 anchor grid")
    }

    static func placement(locale: Locale = .current) -> String {
        String(localized: "Placement", table: table, locale: locale, comment: "Watermark inspector section (iPad): position, size, margin, opacity")
    }

    static func size(locale: Locale = .current) -> String {
        String(localized: "Size", table: table, locale: locale, comment: "Watermark screen: height of the stamp")
    }

    static func margin(locale: Locale = .current) -> String {
        String(localized: "Margin", table: table, locale: locale, comment: "Watermark screen slider: gap from the photo's edges")
    }

    static func opacity(locale: Locale = .current) -> String {
        String(localized: "Opacity", table: table, locale: locale, comment: "Watermark screen slider")
    }

    static func smaller(locale: Locale = .current) -> String {
        String(localized: "Smaller", table: table, locale: locale, comment: "Watermark Size stepper: minus")
    }

    static func larger(locale: Locale = .current) -> String {
        String(localized: "Larger", table: table, locale: locale, comment: "Watermark Size stepper: plus")
    }

    /// `55 px` — Size in pixels of the photo being previewed.
    static func pixelValue(_ pixels: Int, locale: Locale = .current) -> String {
        String(localized: "\(pixels) px", table: table, locale: locale, comment: "Watermark Size in pixels of the previewed photo, e.g. 55 px")
    }

    /// `4% of the short side` — what the pixels mean on every photo.
    static func percentOfShortSide(_ fraction: Double, locale: Locale = .current) -> String {
        let percent = (fraction * 100).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return String(localized: "\(percent)% of the short side", table: table, locale: locale, comment: "Watermark Size: the height as a share of each photo's short side")
    }

    static func sizeInPixels(locale: Locale = .current) -> String {
        String(localized: "Size in Pixels", table: table, locale: locale, comment: "Alert title: type the watermark's height in pixels")
    }

    static func pixels(locale: Locale = .current) -> String {
        String(localized: "Pixels", table: table, locale: locale, comment: "Text field placeholder: watermark height in pixels")
    }

    static func set(locale: Locale = .current) -> String {
        String(localized: "Set", table: table, locale: locale, comment: "Alert button: apply the typed watermark size")
    }

    static func cancel(locale: Locale = .current) -> String {
        String(localized: "Cancel", table: table, locale: locale, comment: "Alert button")
    }

    static func missingFile(locale: Locale = .current) -> String {
        String(localized: "Missing file", table: table, locale: locale, comment: "Watermark preset chip: its logo image is gone; it cannot be chosen")
    }

    static func unavailable(locale: Locale = .current) -> String {
        String(localized: "Unavailable", table: table, locale: locale, comment: "Watermark preset chip: its typeface is gone from this device; a fallback is used")
    }

    /// The line under a preset's name: what it holds, or why it is limited.
    static func chipDetail(_ preset: SignaturePreset, availability: WatermarkAvailability, locale: Locale = .current) -> String {
        switch availability {
        case .available: contents(of: preset, locale: locale)
        case .missingFile: missingFile(locale: locale)
        case .fontUnavailable: unavailable(locale: locale)
        }
    }

    /// What a preset is made of, under its name: `Text + logo`.
    static func contents(of preset: SignaturePreset, locale: Locale = .current) -> String {
        var parts: [String] = []
        let kinds = Set(preset.layers.map(\.kind))
        if kinds.contains(.text) { parts.append(String(localized: "Text", table: table, locale: locale, comment: "Watermark preset contents: a caption")) }
        if kinds.contains(.image) { parts.append(String(localized: "Logo", table: table, locale: locale, comment: "Watermark preset contents: an image")) }
        if kinds.contains(.drawing) { parts.append(String(localized: "Drawing", table: table, locale: locale, comment: "Watermark preset contents: freehand strokes")) }
        if kinds.contains(.shape) { parts.append(String(localized: "Shape", table: table, locale: locale, comment: "Watermark preset contents: a drawn shape")) }
        guard let first = parts.first else { return "" }
        return ([first] + parts.dropFirst().map { $0.lowercased(with: locale) }).joined(separator: " + ")
    }

    /// VoiceOver for one cell of the grid: `Position, bottom right`.
    static func positionLabel(_ anchor: WatermarkAnchor, locale: Locale = .current) -> String {
        let place = switch anchor {
        case .topLeft: String(localized: "top left", table: table, locale: locale, comment: "Watermark position")
        case .top: String(localized: "top", table: table, locale: locale, comment: "Watermark position")
        case .topRight: String(localized: "top right", table: table, locale: locale, comment: "Watermark position")
        case .left: String(localized: "left", table: table, locale: locale, comment: "Watermark position")
        case .center: String(localized: "center", table: table, locale: locale, comment: "Watermark position")
        case .right: String(localized: "right", table: table, locale: locale, comment: "Watermark position")
        case .bottomLeft: String(localized: "bottom left", table: table, locale: locale, comment: "Watermark position")
        case .bottom: String(localized: "bottom", table: table, locale: locale, comment: "Watermark position")
        case .bottomRight: String(localized: "bottom right", table: table, locale: locale, comment: "Watermark position")
        }
        return String(localized: "Position, \(place)", table: table, locale: locale, comment: "VoiceOver: one cell of the watermark position grid")
    }

    /// The phone pill: `3 / 12`.
    static func pagePill(_ index: Int, of count: Int) -> String {
        "\(index) / \(count)"
    }

    /// `3 of 12`.
    static func pageCounter(_ index: Int, of count: Int, locale: Locale = .current) -> String {
        String(localized: "\(index) of \(count)", table: table, locale: locale, comment: "Watermark preview: which photo of the batch is shown")
    }

    static func photoNumber(_ index: Int, current: Bool, locale: Locale = .current) -> String {
        current
            ? String(localized: "Photo \(index), current", table: table, locale: locale, comment: "VoiceOver: filmstrip photo being previewed")
            : String(localized: "Photo \(index)", table: table, locale: locale, comment: "VoiceOver: filmstrip photo")
    }

    /// iPad header's second line: `Resize · 12 photos · 3 of 12`.
    static func padSubtitle(form: String, count: Int, index: Int, locale: Locale = .current) -> String {
        guard count > 1 else { return form }
        let photos = String(localized: "\(count) photos", table: table, locale: locale, comment: "Count of photos in an export (plural)")
        return [form, photos, pageCounter(index, of: count, locale: locale)].joined(separator: " · ")
    }

    static func backTo(_ form: String, locale: Locale = .current) -> String {
        String(localized: "Back to \(form)", table: table, locale: locale, comment: "VoiceOver: the Watermark screen's back button")
    }

    static func collapse(_ section: String, locale: Locale = .current) -> String {
        String(localized: "Collapse \(section)", table: table, locale: locale, comment: "VoiceOver: fold an inspector section")
    }

    static func expand(_ section: String, locale: Locale = .current) -> String {
        String(localized: "Expand \(section)", table: table, locale: locale, comment: "VoiceOver: unfold an inspector section")
    }

    static func noWatermarksYet(locale: Locale = .current) -> String {
        String(localized: "No watermarks yet", table: table, locale: locale, comment: "Watermark screen with no preset saved")
    }

    static func howToMakeOne(locale: Locale = .current) -> String {
        String(localized: "In the editor, open Markup, set up a caption or a logo, then choose Save as Preset.", table: table, locale: locale, comment: "Watermark screen with no preset: where watermarks are made")
    }
}
