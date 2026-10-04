import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07c §3: every way an export goes wrong — how far it reaches and
/// what the user reads.
@Suite struct FileExportFailureTests {
    @Test func eachRowOfTheTable() {
        // One photo: the batch runs on.
        #expect(FileExportFailure.unsupportedRAW.photoReason == "iOS can't read this RAW yet")
        #expect(FileExportFailure.noLongerAvailable.photoReason == "ShotDex can't read this photo anymore.")
        #expect(FileExportFailure.tooLargeForDrive.photoReason == "Too large for this drive's format.")
        for photo: FileExportFailure in [.unreadable, .unsupportedRAW, .noLongerAvailable, .downloadFailed, .tooLargeForDrive, .renderFailed, .stampFailed] {
            #expect(!photo.stopsBatch)
        }
        // The destination: the batch stops.
        for destination: FileExportFailure in [.disconnected, .full, .permissionDenied, .notEnoughSpace(needed: 1, free: 0)] {
            #expect(destination.stopsBatch)
        }
        #expect(ExportCopy.disconnected("T7", done: 199, total: 500) == "“T7” was disconnected. 199 of 500 exported.")
        #expect(ExportCopy.full("T7", done: 212, total: 500) == "“T7” is full — 212 of 500 exported.")
        #expect(ExportCopy.cantWrite == "You can't write to this folder.")
    }

    /// The system's codes, sorted.
    @Test func classifiesCocoaAndPOSIX() {
        #expect(FileExportFailure.classify(CocoaError(.fileWriteOutOfSpace)) == .full)
        #expect(FileExportFailure.classify(CocoaError(.fileWriteNoPermission)) == .permissionDenied)
        #expect(FileExportFailure.classify(CocoaError(.fileWriteVolumeReadOnly)) == .permissionDenied)
        #expect(FileExportFailure.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))) == .tooLargeForDrive)
        #expect(FileExportFailure.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))) == .full)
        #expect(FileExportFailure.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))) == .disconnected)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))])
        #expect(FileExportFailure.classify(wrapped) == .permissionDenied)
        #expect(FileExportRunner.failure(for: PhotoEditingError.unsupportedRAW) == .unsupportedRAW)
        #expect(FileExportRunner.failure(for: OriginalFetchError.missing) == .noLongerAvailable)
    }

    /// The summary for each stop: its words and its way on.
    @Test func summaryOffersTheRightWayOn() {
        let items = (1...5).map { FileExportItem(id: "p\($0)", filename: "IMG_\($0).JPG", captureDate: ExportFixture.date(minutes: $0), kind: .photo, files: []) }
        let plan = FileExportPlan.make(items: items, mode: .currentVersion, template: .originalName, policy: .keepBoth,
                                       dateFolders: false, includesLivePhotoVideo: true, renderExtension: { _ in "jpg" }, existing: [:])
        var report = FileExportReport()
        report.written = ["p1": ["IMG_1.jpg"], "p2": ["IMG_2.jpg"]]
        report.stoppedBy = .disconnected
        let drive = ExportFolder(bookmark: Data(), name: "Exports", place: "T7", path: "/T7/Exports", isOnExternalDrive: true)

        let unplugged = FileExportSummary(plan: plan, report: report, preflight: nil, folder: drive)
        #expect(unplugged.headline == "“T7” was disconnected. 2 of 5 exported.")
        #expect(unplugged.offersExportRemaining && !unplugged.offersAnotherFolder)

        report.stoppedBy = .permissionDenied
        let refused = FileExportSummary(plan: plan, report: report, preflight: nil, folder: drive)
        #expect(refused.headline == "You can't write to this folder.")
        #expect(refused.offersAnotherFolder && !refused.offersExportRemaining)
    }
}

/// FS-03.07c AC-11 (logic half): a drive pulled out stops the batch within
/// two seconds, never hangs; parts left behind go the next time.
@Suite struct LocalFolderWriterTests {
    @Test func disconnectStopsWithinTwoSeconds() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        var writer = LocalFolderWriter(root: fixture.destination)
        let destination = fixture.destination
        // The coordination hangs the way it may on a pulled drive, and the
        // folder is gone.
        writer.rename = { _, _, _, _ in
            try? FileManager.default.removeItem(at: destination)
            Thread.sleep(forTimeInterval: 6)
            return "never"
        }
        let started = Date()

        await #expect(throws: FileExportFailure.disconnected) {
            _ = try await writer.write(name: "IMG_0001.JPG", in: "", replacing: false) { url in
                try Data("bytes".utf8).write(to: url)
            }
        }
        #expect(Date().timeIntervalSince(started) <= 2.5)
    }

    @Test func leftoverPartsAreSweptOnlyByTheirSuffix() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        for name in ["IMG_0001.JPG.shotdex-part", "IMG_0001.JPG", "notes.part", "IMG_0002.shotdex-partial"] {
            try Data("x".utf8).write(to: fixture.destination.appendingPathComponent(name))
        }

        await fixture.writer().sweepLeftoverParts(in: "")

        #expect(fixture.names() == ["IMG_0001.JPG", "IMG_0002.shotdex-partial", "notes.part"])
    }
}

extension FileExportRunnerTests {
    /// The destination fills up at the third photo: the batch stops, its
    /// part is gone, two files stay, and Export Remaining is offered.
    @Test func fullDiskRemovesPartAndOffersRemaining() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        var items: [FileExportItem] = []
        for index in 1...5 {
            let file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: ExportFixture.randomData(10_000))
            items.append(FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
        }
        fixture.source.fail(items[2].files[0].key, with: CocoaError(.fileWriteOutOfSpace))
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal)

        let report = await fixture.runner().run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(report.stoppedBy == .full)
        #expect(fixture.names() == ["IMG_1.JPG", "IMG_2.JPG"])
        let folder = ExportFolder(bookmark: Data(), name: "Exports", place: "On My iPhone", path: fixture.destination.path)
        let summary = FileExportSummary(plan: plan, report: report, preflight: nil, folder: folder)
        #expect(summary.headline == "“Exports” is full — 2 of 5 exported.")
        #expect(summary.offersExportRemaining)
        #expect(report.remaining(in: plan) == ["p3", "p4", "p5"])
    }

    /// The folder vanishes after two files: *disconnected*, not three
    /// hundred identical errors; a photo's own error does not stop it.
    @Test func disconnectStopsTheBatchButAPhotoErrorDoesNot() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        var items: [FileExportItem] = []
        for index in 1...5 {
            let file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: ExportFixture.randomData(10_000))
            items.append(FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
        }
        fixture.source.fail(items[0].files[0].key, with: FileExportFailure.noLongerAvailable)
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal)
        let destination = fixture.destination
        let runner = fixture.runner { event in
            if case .finished(let id, _) = event, id == "p3" { try? FileManager.default.removeItem(at: destination) }
        }

        let report = await runner.run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(report.failed == ["p1": .noLongerAvailable])
        #expect(report.writtenCount == 2)
        #expect(report.stoppedBy == .disconnected)
    }
}
