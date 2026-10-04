import Foundation
import ImageIO
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b/07c: the export run — what lands in the folder, under which
/// names, from which bytes.
@Suite struct FileExportRunnerTests {
    /// The AC-7 batch: a RAF+JPG pair, a Live Photo, a 10 s video.
    private func ac7Items(_ fixture: ExportFixture) throws -> [FileExportItem] {
        let raf = try fixture.file("pair", "DSCF1000.RAF", role: .photo, data: ExportFixture.randomData(3_200_000), isRAW: true)
        let jpg = try fixture.file("pair", "DSCF1000.JPG", role: .alternatePhoto, data: ExportFixture.randomData(900_000))
        let heic = try fixture.file("live", "IMG_0042.HEIC", role: .photo, data: ExportFixture.randomData(400_000))
        let liveMovie = try fixture.file("live", "IMG_0042.MOV", role: .pairedVideo, data: ExportFixture.randomData(700_000))
        let movie = try fixture.file("video", "IMG_0050.MOV", role: .video, data: ExportFixture.randomData(2_500_000))
        return [
            FileExportItem(id: "video", filename: "IMG_0050.MOV", captureDate: ExportFixture.date(minutes: 30), kind: .video, files: [movie]),
            FileExportItem(id: "pair", filename: "DSCF1000.RAF", captureDate: ExportFixture.date(minutes: 5), camera: "X-T5", kind: .photo, files: [raf, jpg]),
            FileExportItem(id: "live", filename: "IMG_0042.HEIC", captureDate: ExportFixture.date(minutes: 10), kind: .livePhoto, files: [heic, liveMovie]),
        ]
    }

    /// AC-7: Unmodified Original with `{date}_{seq}` and Live Photo Video on
    /// — five files, the pair and the Live Photo sharing a name, original
    /// extensions as they were, every byte equal to the original.
    @Test func unmodifiedCopiesEveryOriginalByteForByte() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let items = try ac7Items(fixture)
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal, template: FileNameTemplate("{date}_{seq}"))

        let report = await fixture.runner().run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(report.failed.isEmpty && report.stoppedBy == nil)
        #expect(fixture.names() == [
            "2026-09-20_001.JPG", "2026-09-20_001.RAF", "2026-09-20_002.HEIC", "2026-09-20_002.MOV", "2026-09-20_003.MOV",
        ])
        let pairs: [(String, String)] = [
            ("2026-09-20_001.RAF", "pair-photo-DSCF1000.RAF"), ("2026-09-20_001.JPG", "pair-alternatePhoto-DSCF1000.JPG"),
            ("2026-09-20_002.HEIC", "live-photo-IMG_0042.HEIC"), ("2026-09-20_002.MOV", "live-pairedVideo-IMG_0042.MOV"),
            ("2026-09-20_003.MOV", "video-video-IMG_0050.MOV"),
        ]
        for (written, key) in pairs {
            #expect(try ExportFixture.sha(fixture.destination.appendingPathComponent(written)) == ExportFixture.sha(fixture.source.url(for: key)))
        }
        #expect(!fixture.names().contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        #expect(report.writtenCount == 3)
    }

    /// Live Photo Video off: the still alone.
    @Test func livePhotoVideoSwitch() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let items = try ac7Items(fixture)
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal, template: FileNameTemplate("{date}_{seq}"), livePhotoVideo: false)

        _ = await fixture.runner().run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(fixture.names() == ["2026-09-20_001.JPG", "2026-09-20_001.RAF", "2026-09-20_002.HEIC", "2026-09-20_003.MOV"])
    }

    /// Date Folders: `2026/2026-09-20/…`, like the upload (FS-15.02 §3).
    @Test func dateFoldersNestByDay() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let a = try fixture.file("a", "IMG_0001.HEIC", role: .photo, data: ExportFixture.randomData(10_000))
        let b = try fixture.file("b", "IMG_0002.HEIC", role: .photo, data: ExportFixture.randomData(10_000))
        let items = [
            FileExportItem(id: "a", filename: "IMG_0001.HEIC", captureDate: ExportFixture.date(day: 20), kind: .photo, files: [a]),
            FileExportItem(id: "b", filename: "IMG_0002.HEIC", captureDate: ExportFixture.date(day: 21), kind: .photo, files: [b]),
        ]
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal, dateFolders: true)

        _ = await fixture.runner().run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(fixture.names("2026/2026-09-20") == ["IMG_0001.HEIC"])
        #expect(fixture.names("2026/2026-09-21") == ["IMG_0002.HEIC"])
    }

    // MARK: Current Version (AC-6)

    /// Photo A, edited in Photos (Exposure +1: the render is brighter).
    private func editedPhoto(_ fixture: ExportFixture) throws -> FileExportItem {
        let original = try fixture.file("a", "DSCF2000.JPG", role: .photo, data: ExportFixture.image(width: 4_032, height: 3_024, gray: 0.3))
        let edited = try fixture.file("a", "FullSizeRender.jpg", role: .editedPhoto, data: ExportFixture.image(width: 4_032, height: 3_024, gray: 0.6))
        return FileExportItem(id: "a", filename: "DSCF2000.JPG", captureDate: ExportFixture.date(minutes: 5), camera: "X-T5",
                              kind: .photo, files: [original, edited], pixelWidth: 4_032, pixelHeight: 3_024)
    }

    private func currentJob(_ plan: FileExportPlan, version: FileExportVersion, stamp: (any ExportStamping)? = nil) -> FileExportJob {
        FileExportJob(plan: plan, mode: .currentVersion, version: version,
                      render: FileExportRenderOptions(preset: .twoK, format: .jpeg, quality: 0.8, metadata: .noLocation),
                      stamp: stamp)
    }

    /// AC-6: 2048 px, JPEG 80, No Location — Edited is the version Photos
    /// shows: 2048×1536 and brighter than the Original of the same run; no
    /// GPS; Make, Model and the capture date stay.
    @Test func editedIsTheCurrentVersion() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let item = try editedPhoto(fixture)

        let editedPlan = try fixture.plan([item], mode: .currentVersion, template: FileNameTemplate("{original}_edited"))
        let edited = await fixture.runner().run(currentJob(editedPlan, version: .edited))
        let originalPlan = try fixture.plan([item], mode: .currentVersion, template: FileNameTemplate("{original}_original"))
        let original = await fixture.runner().run(currentJob(originalPlan, version: .original))

        #expect(edited.failed.isEmpty && original.failed.isEmpty)
        let e = try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF2000_edited.jpg")))
        let o = try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF2000_original.jpg")))
        #expect(e.width == 2_048 && e.height == 1_536)
        #expect(e.brightness > o.brightness + 0.2)
        #expect(e.properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = try #require(e.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "FUJIFILM")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "X-T5")
        let exif = try #require(e.properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:20 17:05:12")
    }

    /// Original reads the file as shot, never the edit.
    @Test func originalIgnoresTheEdit() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let item = try editedPhoto(fixture)
        let plan = try fixture.plan([item], mode: .currentVersion)

        _ = await fixture.runner().run(currentJob(plan, version: .original))

        #expect(fixture.source.copies == ["a-photo-DSCF2000.JPG"])
        #expect(fixture.names() == ["DSCF2000.jpg"])
        #expect(try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF2000.jpg"))).brightness < 0.45)
    }

    /// No Location strips GPS; Make, Model and the date stay (covered in
    /// `editedIsTheCurrentVersion`); All Metadata keeps GPS.
    @Test func noLocationKeepsMakeModelDate() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let item = try editedPhoto(fixture)
        let plan = try fixture.plan([item], mode: .currentVersion)
        var job = currentJob(plan, version: .edited)
        job.render.metadata = .all

        _ = await fixture.runner().run(job)

        let read = try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF2000.jpg")))
        #expect(read.properties[kCGImagePropertyGPSDictionary] != nil)
    }

    /// A stamp that makes the picture 10×10: the file is 10×10 — the stamp
    /// ran after the resize and before the write — and still says FUJIFILM.
    struct ShrinkingStamp: ExportStamping {
        func stamp(_ result: PhotoRenderResult, for item: FileExportItem) async throws -> PhotoRenderResult {
            await PhotoRenderService().resize(
                result, preset: ResizePreset(name: "stamp", kind: .exact, width: 10, height: 10, cropMode: .fill), cropAnchor: .center
            )
        }
    }

    struct FailingStamp: ExportStamping {
        struct Refused: Error {}
        func stamp(_ result: PhotoRenderResult, for item: FileExportItem) async throws -> PhotoRenderResult { throw Refused() }
    }

    @Test func stampSitsBetweenRenderAndMetadata() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan([try editedPhoto(fixture)], mode: .currentVersion)

        _ = await fixture.runner().run(currentJob(plan, version: .edited, stamp: ShrinkingStamp()))

        let read = try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF2000.jpg")))
        #expect(read.width == 10 && read.height == 10)
        #expect((read.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String == "FUJIFILM")
    }

    /// A stamp that fails leaves the photo out — never written unstamped.
    @Test func stampFailureNeverWritesUnstamped() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let plan = try fixture.plan([try editedPhoto(fixture)], mode: .currentVersion)

        let report = await fixture.runner().run(currentJob(plan, version: .edited, stamp: FailingStamp()))

        #expect(report.failed["a"] == .stampFailed)
        #expect(fixture.names().isEmpty)
    }

    /// A video at Current Version goes as it is: the edited movie when Photos
    /// has one, byte for byte; a Live Photo is a still.
    @Test func videoGoesAsItIsAndLivePhotoIsAStill() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let movie = try fixture.file("v", "IMG_0050.MOV", role: .video, data: ExportFixture.randomData(300_000))
        let trimmed = try fixture.file("v", "FullSizeRender.mov", role: .editedVideo, data: ExportFixture.randomData(200_000))
        let still = try fixture.file("l", "IMG_0042.HEIC", role: .photo, data: ExportFixture.image(width: 400, height: 300, gray: 0.5, type: .heic))
        let paired = try fixture.file("l", "IMG_0042.MOV", role: .pairedVideo, data: ExportFixture.randomData(100_000))
        let items = [
            FileExportItem(id: "v", filename: "IMG_0050.MOV", captureDate: ExportFixture.date(minutes: 1), kind: .video, files: [movie, trimmed]),
            FileExportItem(id: "l", filename: "IMG_0042.HEIC", captureDate: ExportFixture.date(minutes: 2), kind: .livePhoto, files: [still, paired]),
        ]
        let plan = try fixture.plan(items, mode: .currentVersion)

        _ = await fixture.runner().run(currentJob(plan, version: .edited))

        #expect(fixture.names() == ["IMG_0042.jpg", "IMG_0050.MOV"])
        #expect(try ExportFixture.sha(fixture.destination.appendingPathComponent("IMG_0050.MOV")) == ExportFixture.sha(fixture.source.url(for: trimmed.key)))
    }
}
