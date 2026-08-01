import Foundation

/// The two lines of the photo detail info panel, already fitted to the width
/// the panel actually got.
///
/// Why this is a type and not string-building inside the view: the panel is
/// pinned to 52 pt / 2 lines beside the 52 pt Close button, so on a 393 pt
/// phone each line has ~277 pt — far less than the ~92 characters the seven
/// summary fields want. Tail truncation spent that budget on the *longest,
/// least variable* fields (camera + lens came first) and cut the exposure
/// values off entirely. So the fit is decided here instead: whole tokens are
/// dropped by priority until the line fits, which never leaves a half-word
/// like `RF 100-50…` on screen.
///
/// Priority, from the decision in `spec.md`:
/// - exposure (focal / aperture / shutter / ISO) and file size never drop
/// - the camera model drops when line 2 runs out of width
/// - the lens name is not shown at all; it lives in the Photo Info sheet
struct PhotoInfoPanelSummary: Equatable {
    /// Line 1 — capture date/time only: `Today 14:32`, `Yesterday 14:32`,
    /// `20 Jul 14:32`, `20 Jul 2024 14:32`.
    let titleLine: String
    /// Line 2 — camera model when it fits, then exposure group and file size.
    let detailLine: String?
    /// Every field, undropped, for VoiceOver: what the panel shows depends on
    /// the measured width, what it announces must not.
    let accessibilityText: String

    /// - Parameters:
    ///   - fileSize: live resource size when known, else the indexed row's.
    ///   - fallbackTitle: filename to head line 1 with when the asset has no
    ///     creation date.
    ///   - availableWidth: measured panel content width in points. `0` (the
    ///     first frame, before measurement lands) yields the richest line 2;
    ///     the next frame corrects it.
    ///   - measureDetail: width of a string at line 2's font (`caption2`),
    ///     injected so this stays testable without UIKit. Line 1 needs no
    ///     measure — the relative-day/time text has nothing left to drop.
    init(
        metadata: PhotoMetadata,
        fileSize: Int?,
        fallbackTitle: String?,
        calendar: Calendar = .current,
        now: Date = Date(),
        locale: Locale = .current,
        availableWidth: Double,
        measureDetail: (String) -> Double
    ) {
        let camera = metadata.normalizedCameraModel
        let lensFull = metadata.normalizedLensModel

        let exposure = MetadataFormatter.tokenLine([
            metadata.focalLength.flatMap(MetadataFormatter.focalLength),
            metadata.aperture.flatMap(MetadataFormatter.aperture),
            metadata.shutterSpeedSeconds.flatMap(MetadataFormatter.shutterSpeedCompact)
                ?? metadata.shutterSpeedDisplay,
            metadata.iso.flatMap(MetadataFormatter.iso),
        ])
        let size = fileSize.flatMap(MetadataFormatter.fileSize)

        // Line 1: date/time alone, or the filename when the asset has no date.
        let titleLine = Self.dateText(
            metadata.creationDateValue,
            calendar: calendar,
            now: now,
            locale: locale
        ) ?? fallbackTitle ?? String(localized: "Photo")

        // Line 2: camera + exposure + size, else exposure + size (never dropped).
        let detailFallback = MetadataFormatter.metadataLine([exposure, size])
        let detailLine = Self.firstThatFits(
            [MetadataFormatter.metadataLine([camera, exposure, size]), detailFallback],
            budget: availableWidth / Self.scaleTolerance,
            measure: measureDetail
        ) ?? detailFallback

        let accessibilityText = MetadataFormatter.metadataLine([
            titleLine,
            camera,
            lensFull,
            exposure,
            size,
        ]) ?? titleLine

        self.titleLine = titleLine
        self.detailLine = detailLine
        self.accessibilityText = accessibilityText
    }

    /// Richest candidate whose measured width fits. An unmeasured panel
    /// (`budget <= 0`) takes the first candidate — dropping tokens off a width
    /// we don't know yet would flash a poorer line for one frame.
    private static func firstThatFits(
        _ candidates: [String?],
        budget: Double,
        measure: (String) -> Double
    ) -> String? {
        let real = candidates.compactMap { $0 }
        guard let first = real.first else { return nil }
        guard budget > 0 else { return first }
        return real.first { measure($0) <= budget } ?? real.last
    }

    /// The visible lines carry `minimumScaleFactor(0.92)`, so a candidate up to
    /// ~8% over the measured width still renders whole — counting that in keeps
    /// the camera model on line 2 instead of dropping it for a few points.
    private static let scaleTolerance = 0.92

    /// `Today 14:32` / `Yesterday 14:32` for the last two days, else
    /// `20 Jul 14:32`, and `20 Jul 2024 14:32` across years. Day and time are
    /// formatted apart so the line has no ` at ` spending width.
    private static func dateText(
        _ date: Date?,
        calendar: Calendar,
        now: Date,
        locale: Locale
    ) -> String? {
        guard let date else { return nil }
        // `Date.FormatStyle` takes its time zone from the current one, not from the
        // calendar it is handed — so a caller that passes a calendar in a specific
        // zone (tests do) got the day from that zone and the clock time from
        // another, which can differ by a day.
        var timeStyle = Date.FormatStyle(locale: locale, calendar: calendar).hour().minute()
        timeStyle.timeZone = calendar.timeZone
        let time = date.formatted(timeStyle)
        return "\(dayText(date, calendar: calendar, now: now, locale: locale)) \(time)"
    }

    /// Same relative-day wording as the grid's section headers, minus the wide
    /// month name the panel has no room for.
    private static func dayText(
        _ date: Date,
        calendar: Calendar,
        now: Date,
        locale: Locale
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar)
            .day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }
}
