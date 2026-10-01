import Foundation
import ImageIO
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-08.06 §3 for files that are rendered rather than copied — Save Copy,
/// Paste Edits as copies, Resize: what the renderer writes, by level.
struct MetadataLevelTests {

    /// AC-12, the file: the property dictionaries a render writes, filtered.
    @Test func filteredProperties() {
        let photoA = MetadataFixture.properties
        #expect(MetadataLevel.all.filteredProperties(photoA).keys.count == photoA.keys.count)

        let noLocation = MetadataLevel.noLocation.filteredProperties(photoA)
        #expect(noLocation[kCGImagePropertyGPSDictionary] == nil)
        let iptc = noLocation[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        #expect(iptc[kCGImagePropertyIPTCCity] == nil)
        #expect(iptc[kCGImagePropertyIPTCSubLocation] == nil)
        #expect(iptc[kCGImagePropertyIPTCStarRating] as? Int == MetadataFixture.rating)
        let tiff = noLocation[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == MetadataFixture.make)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == MetadataFixture.model)
        let exif = noLocation[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == MetadataFixture.captureDate)
        #expect(exif[kCGImagePropertyExifSubjectLocation] == nil)

        let none = MetadataLevel.noMetadata.filteredProperties(photoA)
        #expect(Set(none.keys) == [kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary])
        let author = none[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(author[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist)
        #expect(author[kCGImagePropertyTIFFCopyright] as? String == MetadataFixture.copyright)
        #expect(author[kCGImagePropertyTIFFMake] == nil)
        let byline = none[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        #expect(Set(byline.keys) == [kCGImagePropertyIPTCByline, kCGImagePropertyIPTCCopyrightNotice])
    }

    /// AC-12: a Save Copy render of photo A at No Location — the renderer
    /// writes no GPS and keeps the camera and the capture date.
    @Test func renderedCopyAtNoLocation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("level-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photoA = try MetadataFixture.write(.jpeg, in: folder)

        let renderer = PhotoRenderService()
        let source = try await renderer.inspectSource(at: photoA)
        let result = try await renderer.render(source: source, recipe: .identity)
        let copy = folder.appendingPathComponent("copy.jpg")
        try await renderer.write(result, to: copy, format: .jpeg, quality: 1, metadata: .noLocation)

        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: copy) == nil)
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: copy))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == MetadataFixture.make)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == MetadataFixture.model)
        let exif = try #require(MetadataFixture.dictionary(kCGImagePropertyExifDictionary, of: copy))
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == MetadataFixture.captureDate)

        let bare = folder.appendingPathComponent("bare.jpg")
        try await renderer.write(result, to: bare, format: .jpeg, quality: 1, metadata: .noMetadata)
        let props = MetadataFixture.properties(of: bare)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist)
    }
}
