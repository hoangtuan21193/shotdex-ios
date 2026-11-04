import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-67, AC-68: what a Mac thumbnail says, as Settings › General
/// › Thumbnails chooses it.
@Suite struct MacThumbnailInfoTests {
    private func item(focal: Double, equivalent: Double?, filename: String = "DSCF4127.RAF") -> LibraryGridItem {
        LibraryGridItem(assetId: "a", creationDate: 1_800_000_000, mediaType: 1, originalFilename: filename,
                        iso: 800, aperture: 2.8, shutterSpeedDisplay: "1/250", focalLength: focal,
                        equivalentFocalLength: equivalent, width: 6000, height: 4000, fileSize: 25_000_000)
    }

    private func fields(_ shown: Set<ThumbnailInfoFields.Field>, equivalent: Bool = false) -> ThumbnailInfoFields {
        ThumbnailInfoFields(shown: shown, showsFileTypeBadge: true, showsEquivalentFocalLength: equivalent)
    }

    /// AC-67: ISO only, then ISO and shutter — the line carries exactly what is chosen.
    @Test func chosenFieldsOnly() {
        let photo = item(focal: 50, equivalent: 50)
        #expect(fields([.iso]).exposureFragments(for: photo) == ["ISO 800"])
        #expect(fields([.iso, .shutterSpeed]).exposureFragments(for: photo) == ["ISO 800", "1/250"])
        let time = Date(timeIntervalSince1970: 1_800_000_000).formatted(date: .omitted, time: .shortened)
        #expect(fields([.fileName, .captureTime]).caption(for: photo) == "DSCF4127.RAF · \(time)")
        #expect(fields([.captureTime]).caption(for: photo) == time)
        #expect(fields([.iso]).caption(for: photo) == nil)
    }

    /// AC-68: an APS-C 23 mm reads 35 mm as full-frame equivalent and 23 mm actual;
    /// a full-frame 50 mm reads 50 mm either way; no equivalent known falls back to actual.
    @Test func focalEquivalent() {
        let fuji = item(focal: 23, equivalent: 34.5)
        let canon = item(focal: 50, equivalent: 50)
        let focalOnly: Set<ThumbnailInfoFields.Field> = [.focalLength]
        #expect(fields(focalOnly, equivalent: true).exposureFragments(for: fuji) == [MetadataFormatter.focalLength(34.5)!])
        #expect(fields(focalOnly).exposureFragments(for: fuji) == [MetadataFormatter.focalLength(23)!])
        #expect(fields(focalOnly, equivalent: true).exposureFragments(for: canon) == [MetadataFormatter.focalLength(50)!])
        #expect(fields(focalOnly, equivalent: true).exposureFragments(for: item(focal: 23, equivalent: nil))
                == [MetadataFormatter.focalLength(23)!])
    }

    /// Unset keys give the iOS grid's defaults, read by the iOS grid's own reader.
    @Test func defaultsMatchTheIOSGrid() throws {
        let suite = "MacThumbnailInfoTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let loaded = ThumbnailInfoFields.load(from: defaults)
        let iOS = GridMetadataDisplayOptions.load(from: defaults)
        #expect(loaded.showsFileTypeBadge == iOS.showsFileTypeBadge)
        #expect(loaded.showsEquivalentFocalLength == iOS.showsEquivalentFocalLength)
        #expect(loaded.shown.contains(.iso) == iOS.showsISO)
        #expect(loaded.shown.contains(.aperture) == iOS.showsAperture)
        #expect(loaded.shown.contains(.shutterSpeed) == iOS.showsShutter)
        #expect(loaded.shown.contains(.focalLength) == iOS.showsFocal)
        #expect(loaded.shown.contains(.megapixels) == iOS.showsMegapixels)
        #expect(loaded.shown.contains(.fileSize) == iOS.showsFileSize)
        #expect(loaded == ThumbnailInfoFields(shown: [.iso, .aperture, .focalLength], showsFileTypeBadge: true,
                                               showsEquivalentFocalLength: false))
        defaults.set(true, forKey: ThumbnailInfoFields.Field.shutterSpeed.key)
        defaults.set(false, forKey: ThumbnailInfoFields.fileTypeBadgeKey)
        let changed = ThumbnailInfoFields.load(from: defaults)
        #expect(changed.shown.contains(.shutterSpeed))
        #expect(!changed.showsFileTypeBadge)
    }

    /// A tile keeps 8pt each side, and the server glyph's width plus 4pt when it shows.
    @Test func roomLeavesTheGlyphClear() {
        #expect(ThumbnailInfoFields.room(side: 160, glyphWidth: nil) == 144)
        #expect(ThumbnailInfoFields.room(side: 160, glyphWidth: 15) == 125)
    }

    /// Trailing fields drop whole to fit; the first always stays.
    @Test func fitsByDroppingTrailingFields() {
        let width: (String) -> Double = { Double($0.count) }
        #expect(ThumbnailInfoFields.fitted(["ISO 800", "50mm", "f/2.8"], width: width, within: 14) == "ISO 800 · 50mm")
        #expect(ThumbnailInfoFields.fitted(["ISO 800", "50mm"], width: width, within: 3) == "ISO 800")
    }
}
