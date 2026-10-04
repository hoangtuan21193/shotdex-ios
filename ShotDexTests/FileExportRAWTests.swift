import Foundation
import ImageIO
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07c AC-8 / FS-03.04b §4: a RAW the decoder reads renders; one it
/// can't falls back to the pair's JPEG; alone, it goes to the summary —
/// never a preview in its place.
extension FileExportRunnerTests {
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.sony) && RAWFixtures.has(RAWFixtures.fuji)))
    func unreadableRAWOnlyIsListed() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let scratch = fixture.root.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let arw = try Data(contentsOf: try #require(RAWFixtures.available(RAWFixtures.sony)))
        let unsupported = try Data(contentsOf: try #require(try RAWFixtures.unsupportedCamera(in: scratch)))

        var items: [FileExportItem] = []
        for (index, name) in ["DSC00001.ARW", "DSC00002.ARW"].enumerated() {
            let file = try fixture.file("arw\(index)", name, role: .photo, data: arw, isRAW: true)
            items.append(FileExportItem(id: "arw\(index)", filename: name, captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
        }
        let rawOnly = try fixture.file("only", "DSCF0412.RAF", role: .photo, data: unsupported, isRAW: true)
        items.append(FileExportItem(id: "only", filename: "DSCF0412.RAF", captureDate: ExportFixture.date(minutes: 5), kind: .photo, files: [rawOnly]))
        let pairRAW = try fixture.file("pair", "DSCF0500.RAF", role: .photo, data: unsupported, isRAW: true)
        let pairJPEG = try fixture.file("pair", "DSCF0500.JPG", role: .alternatePhoto,
                                        data: ExportFixture.image(width: 3_000, height: 2_000, gray: 0.5))
        items.append(FileExportItem(id: "pair", filename: "DSCF0500.RAF", captureDate: ExportFixture.date(minutes: 6),
                                    kind: .photo, files: [pairRAW, pairJPEG]))
        let plan = try fixture.plan(items, mode: .currentVersion)
        let job = FileExportJob(plan: plan, mode: .currentVersion, version: .edited,
                                render: FileExportRenderOptions(preset: .social, format: .jpeg, quality: 0.8, metadata: .all))

        let report = await fixture.runner().run(job)

        #expect(fixture.names() == ["DSC00001.jpg", "DSC00002.jpg", "DSCF0500.jpg"])
        for name in fixture.names() {
            let read = try #require(ExportFixture.read(fixture.destination.appendingPathComponent(name)))
            #expect(max(read.width, read.height) == 1_080, "\(name) is \(read.width)×\(read.height)")
        }
        #expect(report.failed == ["only": .unsupportedRAW])
        #expect(FileExportFailure.unsupportedRAW.photoReason == "iOS can't read this RAW yet")
        let summary = FileExportSummary(plan: plan, report: report, preflight: nil, folder: nil)
        #expect(summary.failures == [.init(name: "DSCF0412.RAF", reason: "iOS can't read this RAW yet")])
        #expect(summary.offersRetry)
    }

    /// The pair's RAW is tried first and its JPEG read only on refusal.
    @Test func pairFallsBackToItsJPEG() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let junk = try RAWFixtures.junk(extension: "RAF", in: fixture.root)
        let raw = try fixture.file("pair", "DSCF0500.RAF", role: .photo, data: try Data(contentsOf: junk), isRAW: true)
        let jpeg = try fixture.file("pair", "DSCF0500.JPG", role: .alternatePhoto, data: ExportFixture.image(width: 2_400, height: 1_600, gray: 0.5))
        let item = FileExportItem(id: "pair", filename: "DSCF0500.RAF", captureDate: ExportFixture.date(), kind: .photo, files: [raw, jpeg])
        let plan = try fixture.plan([item], mode: .currentVersion)

        let report = await fixture.runner().run(FileExportJob(plan: plan, mode: .currentVersion,
                                                              render: FileExportRenderOptions(preset: .social, format: .jpeg)))

        #expect(report.failed.isEmpty)
        #expect(fixture.source.copies == [raw.key, jpeg.key])
        #expect(try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSCF0500.jpg"))).width == 1_080)
    }

    /// A readable ARW renders from the RAW itself at 1080.
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.sony)))
    func readableARWRendersAt1080() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let arw = try fixture.file("a", "DSC00001.ARW", role: .photo,
                                   data: try Data(contentsOf: try #require(RAWFixtures.available(RAWFixtures.sony))), isRAW: true)
        let plan = try fixture.plan([FileExportItem(id: "a", filename: "DSC00001.ARW", captureDate: ExportFixture.date(), kind: .photo, files: [arw])],
                                    mode: .currentVersion)

        let report = await fixture.runner().run(FileExportJob(plan: plan, mode: .currentVersion,
                                                              render: FileExportRenderOptions(preset: .social, format: .jpeg)))

        #expect(report.failed.isEmpty)
        let read = try #require(ExportFixture.read(fixture.destination.appendingPathComponent("DSC00001.jpg")))
        #expect(max(read.width, read.height) == 1_080)
        #expect((read.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "ILCE-7M3")
    }
}
