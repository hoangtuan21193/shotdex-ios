import Foundation
import Testing
@testable import ShotDex

struct PhotoInfoPanelSummaryTests {

    /// Stand-in for text measurement: 5.6 pt per character is roughly what
    /// `caption2` averages, which is all the fit logic needs to be exercised.
    private static let pointsPerCharacter = 5.6

    private static func measure(_ text: String) -> Double {
        Double(text.count) * pointsPerCharacter
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 20 Jul 2026, 16:32 UTC.
    private static let shotDate = Date(timeIntervalSince1970: 1_784_651_520)

    private static func metadata(
        camera: String? = "Canon EOS R6",
        lens: String? = "RF 100-500mm F4.5-7.1 L IS USM",
        date: Date? = Self.shotDate
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: "asset-1",
            creationDate: date.map { Int($0.timeIntervalSince1970) },
            modificationDate: nil,
            mediaType: 1,
            cameraManufacturer: "Canon",
            cameraModel: camera,
            normalizedCameraModel: camera,
            normalizedCameraManufacturer: "Canon",
            lensManufacturer: nil,
            lensModel: lens,
            normalizedLensModel: lens,
            originalFilename: "IMG_0001.CR3",
            iso: 3200,
            aperture: 7.1,
            shutterSpeedSeconds: 1.0 / 1000,
            shutterSpeedDisplay: FormatUtils.shutterSpeed(1.0 / 1000),
            focalLength: 400,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: 28_400_000,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: 0,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private static func make(
        _ metadata: PhotoMetadata,
        width: Double,
        now: Date = Self.shotDate
    ) -> PhotoInfoPanelSummary {
        PhotoInfoPanelSummary.make(
            metadata: metadata,
            fileSize: metadata.fileSize,
            fallbackTitle: "IMG_0001.CR3",
            calendar: calendar,
            now: now,
            locale: Locale(identifier: "en_GB"),
            availableWidth: width,
            measureDetail: measure
        )
    }

    @Test func widePanelKeepsCameraAndExposure() {
        let summary = Self.make(Self.metadata(), width: 900)

        #expect(summary.detailLine == "Canon EOS R6 · 400mm f/7.1 1/1000 ISO 3200 · 28.4 MB")
    }

    @Test func lensNameIsNeverShown() {
        let summary = Self.make(Self.metadata(), width: 900)

        #expect(summary.titleLine.contains("RF 100-500mm") == false)
        #expect(summary.detailLine?.contains("RF 100-500mm") == false)
    }

    @Test func cameraDropsWhenLineTwoIsTight() {
        // Fits "400mm f/7.1 1/1000 ISO 3200 · 28.4 MB" (37 chars) but not camera.
        let summary = Self.make(Self.metadata(), width: 220)

        #expect(summary.detailLine?.contains("Canon EOS R6") == false)
        #expect(summary.detailLine == "400mm f/7.1 1/1000 ISO 3200 · 28.4 MB")
    }

    @Test func exposureAndFileSizeSurviveAnyWidth() {
        let summary = Self.make(Self.metadata(), width: 1)

        #expect(summary.detailLine?.contains("400mm f/7.1 1/1000 ISO 3200") == true)
        #expect(summary.detailLine?.contains("28.4 MB") == true)
    }

    @Test func accessibilityTextKeepsEveryFieldAtAnyWidth() {
        let summary = Self.make(Self.metadata(), width: 1)

        #expect(summary.accessibilityText.contains("Canon EOS R6"))
        // The lens is hidden on screen but still announced, in full.
        #expect(summary.accessibilityText.contains("RF 100-500mm F4.5-7.1 L IS USM"))
        #expect(summary.accessibilityText.contains("ISO 3200"))
        #expect(summary.accessibilityText.contains("28.4 MB"))
    }

    @Test func unmeasuredWidthUsesRichestLine() {
        let summary = Self.make(Self.metadata(), width: 0)

        #expect(summary.detailLine?.contains("Canon EOS R6") == true)
    }

    @Test func todayAndYesterdayReplaceTheDate() {
        let today = Self.make(Self.metadata(), width: 900)
        #expect(today.titleLine == "Today 16:32")

        // 19 Jul 2026, 16:32 UTC — one day before `now`.
        let yesterdayShot = Date(timeIntervalSince1970: 1_784_565_120)
        let yesterday = Self.make(Self.metadata(date: yesterdayShot), width: 900)
        #expect(yesterday.titleLine == "Yesterday 16:32")
    }

    @Test func olderDatesShowDayAndMonthWithoutAt() {
        // 10 Jul 2026, 16:32 UTC — same year, more than a day back.
        let sameYear = Date(timeIntervalSince1970: 1_783_787_520)
        let summary = Self.make(Self.metadata(date: sameYear), width: 900)
        #expect(summary.titleLine == "10 Jul 16:32")
        #expect(!summary.titleLine.contains(" at "))
        #expect(!summary.titleLine.contains("2026"))

        let twoYearsEarlier = Date(timeIntervalSince1970: 1_721_493_120)  // 20 Jul 2024, 16:32 UTC
        let older = Self.make(Self.metadata(date: twoYearsEarlier), width: 900)
        #expect(older.titleLine == "20 Jul 2024 16:32")
    }

    @Test func missingGearLeavesNoOrphanSeparator() {
        let summary = Self.make(Self.metadata(camera: nil, lens: nil), width: 900)

        #expect(summary.detailLine == "400mm f/7.1 1/1000 ISO 3200 · 28.4 MB")
    }

    @Test func noDateFallsBackToFilename() {
        let summary = Self.make(Self.metadata(date: nil), width: 900)

        #expect(summary.titleLine == "IMG_0001.CR3")
    }
}
