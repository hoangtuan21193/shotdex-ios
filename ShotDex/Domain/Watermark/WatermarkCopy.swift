import Foundation

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

    /// The reason beside each of those photos.
    static func nothingToStamp(preset: String, locale: Locale = .current) -> String {
        String(localized: "Every part of \(preset) is empty for this photo.", table: table, locale: locale, comment: "Resize summary: why a photo has no watermark — its tokens all came out empty")
    }

    static func withoutWatermarkSection(locale: Locale = .current) -> String {
        String(localized: "Without Watermark", table: table, locale: locale, comment: "Resize summary section: photos that went without the watermark")
    }
}
