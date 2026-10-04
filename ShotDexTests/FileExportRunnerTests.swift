import Foundation
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
}
